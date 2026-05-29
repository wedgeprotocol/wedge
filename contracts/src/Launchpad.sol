// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LaunchDeployer} from "./LaunchDeployer.sol";
import {LaunchToken} from "./LaunchToken.sol";
import {OwnerAdmins} from "./base/OwnerAdmins.sol";
import {IWedgeExtension} from "./interfaces/IWedgeExtension.sol";
import {IWedgeHook} from "./interfaces/IWedgeHook.sol";
import {IWedgeLpLocker} from "./interfaces/IWedgeLpLocker.sol";
import {IWedgeMevModule} from "./interfaces/IWedgeMevModule.sol";

/// @notice Launchpad — the factory that deploys `LaunchToken`s and
///         wires them into Uniswap v4 pools, lockers, MEV modules, and
///         optional extensions in a single transaction.
///
///         All hook / locker / extension / MEV module contracts are
///         allowlisted by owner before they can be used in a deployment.
///         No deployment-time configuration baked into this contract is
///         tied to any external address; treasury, protocol token, and
///         allowlists are all settable post-deploy.
///
///         Fee transparency note: the Mainline hook is expected to take
///         a fixed protocol fee out of the LP-fee stream on every swap.
///         Creators receive the LP-fee remainder distributed via the
///         locker's reward arrays — not the full LP fee. Public copy
///         must reflect that split honestly.
contract Launchpad is OwnerAdmins, ReentrancyGuard {
    string public constant PROTOCOL = "Wedge";
    string public constant VERSION = "1";

    uint256 public constant TOKEN_SUPPLY = 100_000_000_000e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_EXTENSIONS = 10;
    uint16 public constant MAX_EXTENSION_BPS = 9000;

    // ─────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────

    struct PoolConfig {
        address hook;
        address pairedToken;
        int24 tickIfToken0IsLaunched;
        int24 tickSpacing;
        bytes poolData;
    }

    struct LockerConfig {
        address locker;
        address[] rewardAdmins;
        address[] rewardRecipients;
        uint16[] rewardBps;
        int24[] tickLower;
        int24[] tickUpper;
        uint16[] positionBps;
        bytes lockerData;
    }

    struct MevModuleConfig {
        address mevModule;
        bytes mevModuleData;
    }

    struct ExtensionConfig {
        address extension;
        uint256 msgValue;
        uint16 extensionBps;
        bytes extensionData;
    }

    struct DeploymentConfig {
        LaunchDeployer.TokenConfig tokenConfig;
        PoolConfig poolConfig;
        LockerConfig lockerConfig;
        MevModuleConfig mevModuleConfig;
        ExtensionConfig[] extensionConfigs;
    }

    struct DeploymentInfo {
        address token;
        address hook;
        address locker;
        address[] extensions;
    }

    // ─────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────

    error Deprecated();
    error InvalidHook();
    error InvalidLocker();
    error InvalidExtension();
    error InvalidMevModule();
    error HookNotEnabled();
    error LockerNotEnabled();
    error ExtensionNotEnabled();
    error MevModuleNotEnabled();
    error ExtensionMsgValueMismatch();
    error MaxExtensionsExceeded();
    error MaxExtensionBpsExceeded();
    error TeamFeeRecipientNotSet();
    error BadToken();
    error ProtocolTokenAlreadySet();
    error ProtocolTokenNotSet();

    // ─────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────

    bool public deprecated;
    address public teamFeeRecipient;

    /// @notice The protocol token paired against every launch on the
    ///         Wedge Rail. Set once by owner, after which it cannot
    ///         be changed. Until set, extensions whose
    ///         `requiresProtocolToken()` returns true revert.
    address public PROTOCOL_TOKEN;

    mapping(address token => DeploymentInfo deploymentInfo) public deploymentInfoForToken;

    mapping(address hook => bool enabled) public enabledHooks;
    mapping(address locker => mapping(address hook => bool enabled)) public enabledLockers;
    mapping(address extension => bool enabled) public enabledExtensions;
    mapping(address mevModule => bool enabled) public enabledMevModules;

    // ─────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────

    event TokenCreated(
        address indexed msgSender,
        address indexed tokenAddress,
        address indexed tokenAdmin,
        string tokenName,
        string tokenSymbol,
        string tokenImage,
        string tokenMetadata,
        string tokenContext,
        int24 startingTick,
        address poolHook,
        bytes32 poolId,
        address pairedToken,
        address locker,
        address mevModule,
        uint256 extensionsSupply,
        address[] extensions,
        bool renouncedAtDeploy
    );
    event ExtensionTriggered(address extension, uint256 extensionSupply, uint256 msgValue);

    event SetDeprecated(bool deprecated);
    event SetExtension(address extension, bool enabled);
    event SetHook(address hook, bool enabled);
    event SetMevModule(address mevModule, bool enabled);
    event SetLocker(address locker, address hook, bool enabled);
    event SetTeamFeeRecipient(address oldRecipient, address newRecipient);
    event ProtocolTokenSet(address indexed protocolToken);
    event ClaimTeamFees(address indexed token, address indexed recipient, uint256 amount);

    // ─────────────────────────────────────────────────────────────────
    // Construction & ownership
    // ─────────────────────────────────────────────────────────────────

    constructor(address owner_) OwnerAdmins(owner_) {
        // Factory starts deprecated; owner flips this after wiring up
        // hooks/lockers/MEV modules/extensions via the setters below.
        deprecated = true;
    }

    function setDeprecated(bool deprecated_) external onlyOwner {
        deprecated = deprecated_;
        emit SetDeprecated(deprecated_);
    }

    function setTeamFeeRecipient(address newRecipient) external onlyOwner {
        address oldRecipient = teamFeeRecipient;
        teamFeeRecipient = newRecipient;
        emit SetTeamFeeRecipient(oldRecipient, newRecipient);
    }

    /// @notice One-time setter for the protocol token. After this is
    ///         called, extensions whose `requiresProtocolToken()`
    ///         returns true become eligible.
    function setProtocolToken(address protocolToken) external onlyOwner {
        if (PROTOCOL_TOKEN != address(0)) revert ProtocolTokenAlreadySet();
        PROTOCOL_TOKEN = protocolToken;
        emit ProtocolTokenSet(protocolToken);
    }

    function claimTeamFees(address token) external onlyOwnerOrAdmin {
        if (teamFeeRecipient == address(0)) revert TeamFeeRecipientNotSet();
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(token), teamFeeRecipient, balance);
        emit ClaimTeamFees(token, teamFeeRecipient, balance);
    }

    // ─────────────────────────────────────────────────────────────────
    // Allowlist setters
    // ─────────────────────────────────────────────────────────────────

    function setHook(address hook, bool enabled) external onlyOwnerOrAdmin {
        if (!IWedgeHook(hook).supportsInterface(type(IWedgeHook).interfaceId)) {
            revert InvalidHook();
        }
        enabledHooks[hook] = enabled;
        emit SetHook(hook, enabled);
    }

    function setLocker(address locker, address hook, bool enabled) external onlyOwnerOrAdmin {
        if (!IWedgeLpLocker(locker).supportsInterface(type(IWedgeLpLocker).interfaceId)) {
            revert InvalidLocker();
        }
        enabledLockers[locker][hook] = enabled;
        emit SetLocker(locker, hook, enabled);
    }

    function setMevModule(address mevModule, bool enabled) external onlyOwnerOrAdmin {
        if (!IWedgeMevModule(mevModule).supportsInterface(type(IWedgeMevModule).interfaceId)) {
            revert InvalidMevModule();
        }
        enabledMevModules[mevModule] = enabled;
        emit SetMevModule(mevModule, enabled);
    }

    function setExtension(address extension, bool enabled) external onlyOwnerOrAdmin {
        if (!IWedgeExtension(extension).supportsInterface(type(IWedgeExtension).interfaceId)) {
            revert InvalidExtension();
        }
        enabledExtensions[extension] = enabled;
        emit SetExtension(extension, enabled);
    }

    // ─────────────────────────────────────────────────────────────────
    // Deploy
    // ─────────────────────────────────────────────────────────────────

    function deployToken(DeploymentConfig calldata config)
        external
        payable
        nonReentrant
        returns (address tokenAddress)
    {
        if (deprecated) revert Deprecated();

        // Step 1: deploy the token via CREATE2. Renouncement happens
        // atomically in the LaunchToken constructor when the creator
        // opted into it — no two-step admin-rotation race window.
        tokenAddress = LaunchDeployer.deploy(config.tokenConfig, TOKEN_SUPPLY);

        // Step 1a: defensive check that the deployed bytecode is actually
        // a `LaunchToken` (its PROTOCOL constant equals "Wedge"). The
        // deployer is under our control so this should always pass; the
        // check is a belt-and-suspenders guard against deployer hijack.
        _assertIsLaunchToken(tokenAddress);

        // Step 2: split supply between extensions and pool liquidity.
        uint256 extensionsSupply = _prepareExtensions(config.extensionConfigs);
        uint256 poolSupply = TOKEN_SUPPLY - extensionsSupply;

        // Step 3: initialise the pool via the configured hook.
        PoolKey memory poolKey = _initializePool(
            config.poolConfig,
            config.lockerConfig.locker,
            config.mevModuleConfig.mevModule,
            tokenAddress
        );

        // Step 4: place the liquidity via the configured locker.
        _initializeLiquidity(
            config.lockerConfig, config.poolConfig, poolKey, poolSupply, tokenAddress
        );

        // Step 5: trigger any extensions. Each extension receives its
        // share of supply and (optionally) some ETH from msg.value.
        _triggerExtensions(config.extensionConfigs, tokenAddress);

        // Step 6: initialise the MEV module on the hook.
        _initializeMevModule(config.mevModuleConfig, config.poolConfig.hook, poolKey);

        // Step 7: record the deployment.
        address[] memory extensions = new address[](config.extensionConfigs.length);
        for (uint256 i = 0; i < config.extensionConfigs.length; i++) {
            extensions[i] = config.extensionConfigs[i].extension;
        }
        deploymentInfoForToken[tokenAddress] = DeploymentInfo({
            token: tokenAddress,
            hook: config.poolConfig.hook,
            locker: config.lockerConfig.locker,
            extensions: extensions
        });

        // Step 8: emit the canonical TokenCreated event for indexers.
        emit TokenCreated({
            msgSender: msg.sender,
            tokenAddress: tokenAddress,
            tokenAdmin: config.tokenConfig.admin,
            tokenName: config.tokenConfig.name,
            tokenSymbol: config.tokenConfig.symbol,
            tokenImage: config.tokenConfig.image,
            tokenMetadata: config.tokenConfig.metadata,
            tokenContext: config.tokenConfig.context,
            startingTick: config.poolConfig.tickIfToken0IsLaunched,
            poolHook: config.poolConfig.hook,
            poolId: keccak256(abi.encode(poolKey)),
            pairedToken: config.poolConfig.pairedToken,
            locker: config.lockerConfig.locker,
            mevModule: config.mevModuleConfig.mevModule,
            extensionsSupply: extensionsSupply,
            extensions: extensions,
            renouncedAtDeploy: config.tokenConfig.renounceAtDeploy
        });
    }

    function tokenDeploymentInfo(address token) external view returns (DeploymentInfo memory) {
        return deploymentInfoForToken[token];
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal: choreography
    // ─────────────────────────────────────────────────────────────────

    function _assertIsLaunchToken(address token) internal view {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("PROTOCOL()"));
        if (!ok || data.length < 64) revert BadToken();
        string memory name = abi.decode(data, (string));
        if (keccak256(bytes(name)) != keccak256(bytes(PROTOCOL))) revert BadToken();
    }

    function _initializePool(
        PoolConfig calldata poolConfig,
        address locker,
        address mevModule,
        address tokenLaunched
    ) internal returns (PoolKey memory) {
        if (!enabledHooks[poolConfig.hook]) revert HookNotEnabled();
        return IWedgeHook(poolConfig.hook)
            .initializePool(
                tokenLaunched,
                poolConfig.pairedToken,
                poolConfig.tickIfToken0IsLaunched,
                poolConfig.tickSpacing,
                locker,
                mevModule,
                poolConfig.poolData
            );
    }

    function _initializeLiquidity(
        LockerConfig calldata lockerConfig,
        PoolConfig calldata poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) internal {
        if (!enabledLockers[lockerConfig.locker][poolConfig.hook]) {
            revert LockerNotEnabled();
        }

        IERC20(token).approve(lockerConfig.locker, poolSupply);

        IWedgeLpLocker.PlaceLiquidityConfig memory placeConfig = IWedgeLpLocker.PlaceLiquidityConfig({
            rewardAdmins: lockerConfig.rewardAdmins,
            rewardRecipients: lockerConfig.rewardRecipients,
            rewardBps: lockerConfig.rewardBps,
            tickLower: lockerConfig.tickLower,
            tickUpper: lockerConfig.tickUpper,
            positionBps: lockerConfig.positionBps,
            lockerData: lockerConfig.lockerData
        });

        IWedgeLpLocker(lockerConfig.locker)
            .placeLiquidity(
                placeConfig,
                poolKey,
                poolConfig.tickIfToken0IsLaunched,
                poolConfig.tickSpacing,
                poolSupply,
                token
            );
    }

    function _initializeMevModule(
        MevModuleConfig calldata mevConfig,
        address hook,
        PoolKey memory poolKey
    ) internal {
        if (!enabledMevModules[mevConfig.mevModule]) revert MevModuleNotEnabled();
        IWedgeHook(hook).initializeMevModule(poolKey, mevConfig.mevModuleData);
    }

    function _prepareExtensions(ExtensionConfig[] calldata extensions)
        internal
        view
        returns (uint256 extensionSupply)
    {
        uint256 n = extensions.length;
        if (n == 0) return 0;
        if (n > MAX_EXTENSIONS) revert MaxExtensionsExceeded();

        uint256 totalBps;
        uint256 expectedEth;
        for (uint256 i = 0; i < n; i++) {
            totalBps += extensions[i].extensionBps;
            expectedEth += extensions[i].msgValue;
            if (!enabledExtensions[extensions[i].extension]) revert ExtensionNotEnabled();

            // Guard: any extension that requires the protocol token may
            // not run until `setProtocolToken` has been called.
            if (
                IWedgeExtension(extensions[i].extension).requiresProtocolToken()
                    && PROTOCOL_TOKEN == address(0)
            ) {
                revert ProtocolTokenNotSet();
            }
        }
        if (totalBps > MAX_EXTENSION_BPS) revert MaxExtensionBpsExceeded();
        if (expectedEth != msg.value) revert ExtensionMsgValueMismatch();

        extensionSupply = totalBps * TOKEN_SUPPLY / BPS;
    }

    function _triggerExtensions(ExtensionConfig[] calldata extensions, address token) internal {
        for (uint256 i = 0; i < extensions.length; i++) {
            uint256 supplyForExt = uint256(extensions[i].extensionBps) * TOKEN_SUPPLY / BPS;
            if (supplyForExt > 0) {
                IERC20(token).approve(extensions[i].extension, supplyForExt);
            }
            IWedgeExtension(extensions[i].extension).receiveTokens{value: extensions[i].msgValue}(
                token, supplyForExt, extensions[i].extensionData
            );
            emit ExtensionTriggered(extensions[i].extension, supplyForExt, extensions[i].msgValue);
        }
    }
}
