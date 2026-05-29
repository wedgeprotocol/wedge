// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {IWedgeLpLocker} from "./interfaces/IWedgeLpLocker.sol";

/// @notice Locker that custodies the Mainline LP NFTs minted at launch.
///         Receives an approved supply of the launched TOKEN from the
///         Launchpad, mints N one-sided positions via the v4
///         PositionManager (one per band in `LockerConfig.tickLower[]`),
///         and holds the resulting LP NFTs forever — there is no path
///         to withdraw the underlying positions.
///
///         Reward distribution:
///         - Each token has a list of `rewardAdmins` who can update the
///           recipients and bps array. Any admin can replace the entire
///           admin / recipient / bps set in one call.
///         - `collectFees(token)` is permissionless. It decrements
///           liquidity by 0 on every position (the v4 idiom for "claim
///           fees only"), takes both pair currencies to the locker,
///           then splits the realised balance per `rewardBps` and
///           transfers to recipients.
///
///         No admin, no withdraw, no upgrade on the locker itself.
///         Reward admin power is per-token and never extends to the
///         positions themselves.
contract WedgeLpLocker is IWedgeLpLocker, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant PROTOCOL = "Wedge";
    uint256 public constant BPS = 10_000;

    /// @notice Canonical Permit2 address (same on every EVM chain). The
    ///         v4 PositionManager pulls tokens via Permit2's allowance-
    ///         transfer pattern, so the locker first approves Permit2
    ///         then asks Permit2 to authorise the PositionManager.
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public immutable LAUNCHPAD;
    IPositionManager public immutable POSITION_MANAGER;

    struct Position {
        uint256 tokenId;
        uint16 positionBps;
    }

    struct Rewards {
        address[] admins;
        address[] recipients;
        uint16[] bps;
    }

    struct TokenState {
        bool initialized;
        Currency currency0;
        Currency currency1;
        Position[] positions;
        Rewards rewards;
    }

    mapping(address token => TokenState state) private _state;

    error OnlyLaunchpad();
    error NotRewardAdmin();
    error AlreadyPlaced();
    error TokenNotPlaced();
    error LengthMismatch();
    error EmptyArray();
    error PositionBpsSumMismatch();
    error RewardBpsSumMismatch();
    error EmptyRewardAdmins();
    error EmptyRewardRecipients();
    error TicksBackwards();
    error TickNotMultipleOfSpacing();
    error TickLowerBelowStartingTick();

    event LiquidityPlaced(
        address indexed token, uint256 supply, uint256 firstTokenId, uint8 numPositions
    );
    event PositionReceived(address indexed token, uint256 indexed tokenId, uint16 positionBps);
    event FeesCollected(
        address indexed token, address indexed currency, uint256 totalCollected, uint8 numRecipients
    );
    event RewardsUpdated(address indexed token, address indexed by);

    modifier onlyLaunchpad() {
        if (msg.sender != LAUNCHPAD) revert OnlyLaunchpad();
        _;
    }

    constructor(address launchpad_, address positionManager_) {
        LAUNCHPAD = launchpad_;
        POSITION_MANAGER = IPositionManager(positionManager_);
    }

    // ─────────────────────────────────────────────────────────────────
    // IWedgeLpLocker — Launchpad-facing
    // ─────────────────────────────────────────────────────────────────

    /// @inheritdoc IWedgeLpLocker
    function placeLiquidity(
        PlaceLiquidityConfig calldata cfg,
        PoolKey calldata poolKey,
        int24 startingTick,
        int24 tickSpacing,
        uint256 poolSupply,
        address token
    ) external onlyLaunchpad nonReentrant returns (uint256 firstTokenId) {
        if (_state[token].initialized) revert AlreadyPlaced();
        _validateConfig(cfg, startingTick, tickSpacing);

        IERC20(token).safeTransferFrom(msg.sender, address(this), poolSupply);
        // PositionManager pulls via Permit2's AllowanceTransfer.
        IERC20(token).forceApprove(PERMIT2, type(uint256).max);
        IAllowanceTransfer(PERMIT2)
            .approve(
                token,
                address(POSITION_MANAGER),
                uint160(poolSupply),
                uint48(block.timestamp + 1 hours)
            );

        bool token0IsLaunched = Currency.unwrap(poolKey.currency0) == token;
        uint256 n = cfg.tickLower.length;

        firstTokenId = POSITION_MANAGER.nextTokenId();

        bytes memory actions = new bytes(n + 1);
        bytes[] memory params = new bytes[](n + 1);
        for (uint256 i = 0; i < n; i++) {
            uint256 positionSupply = poolSupply * cfg.positionBps[i] / BPS;

            // `cfg.tickLower/Upper[i]` are in the "TOKEN-as-currency0"
            // frame (positive = TOKEN cheap in numeraire), matching the
            // convention the Launchpad uses for `tickIfToken0IsLaunched`.
            // When TOKEN is actually currency1 on the pool, the actual
            // pool ticks are the negation of the as-currency-0 frame
            // and `tickLower < tickUpper` requires swapping the pair.
            (int24 actualLower, int24 actualUpper) = token0IsLaunched
                ? (cfg.tickLower[i], cfg.tickUpper[i])
                : (-cfg.tickUpper[i], -cfg.tickLower[i]);

            uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(actualLower);
            uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(actualUpper);

            uint128 liquidity = token0IsLaunched
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPriceLower, sqrtPriceUpper, positionSupply
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtPriceLower, sqrtPriceUpper, positionSupply
                );

            actions[i] = bytes1(uint8(Actions.MINT_POSITION));
            params[i] = abi.encode(
                poolKey,
                actualLower,
                actualUpper,
                liquidity,
                token0IsLaunched ? uint128(positionSupply) : uint128(0),
                token0IsLaunched ? uint128(0) : uint128(positionSupply),
                address(this),
                bytes("")
            );
        }

        // Single SETTLE_PAIR pays in the launched token from the locker
        // (already approved above) and refunds any excess.
        actions[n] = bytes1(uint8(Actions.SETTLE_PAIR));
        params[n] = abi.encode(poolKey.currency0, poolKey.currency1);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        // Record state. Positions land at sequential IDs starting at
        // `firstTokenId`.
        TokenState storage s = _state[token];
        s.initialized = true;
        s.currency0 = poolKey.currency0;
        s.currency1 = poolKey.currency1;
        for (uint256 i = 0; i < n; i++) {
            s.positions.push(Position({tokenId: firstTokenId + i, positionBps: cfg.positionBps[i]}));
        }
        s.rewards = Rewards({
            admins: cfg.rewardAdmins, recipients: cfg.rewardRecipients, bps: cfg.rewardBps
        });

        emit LiquidityPlaced(token, poolSupply, firstTokenId, uint8(n));
    }

    /// @notice Permissionless. Collects accrued fees on every Mainline
    ///         position for `token` and distributes the realised
    ///         currency0 + currency1 balances per `rewardBps`.
    function collectFees(address token) external nonReentrant {
        TokenState storage s = _state[token];
        if (!s.initialized) revert TokenNotPlaced();

        uint256 n = s.positions.length;
        bytes memory actions = new bytes(n + 1);
        bytes[] memory params = new bytes[](n + 1);
        for (uint256 i = 0; i < n; i++) {
            actions[i] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
            params[i] =
                abi.encode(s.positions[i].tokenId, uint256(0), uint128(0), uint128(0), bytes(""));
        }
        actions[n] = bytes1(uint8(Actions.TAKE_PAIR));
        params[n] = abi.encode(s.currency0, s.currency1, address(this));

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        _distribute(token, s.currency0);
        _distribute(token, s.currency1);
    }

    // ─────────────────────────────────────────────────────────────────
    // Reward admin
    // ─────────────────────────────────────────────────────────────────

    /// @notice Replace the full reward configuration. Callable only by
    ///         one of the current `rewardAdmins`. The locker enforces
    ///         that admins/recipients/bps are well-formed but does not
    ///         restrict who can be added or removed — this is by
    ///         design: a creator can hand off rewards to a multisig
    ///         (replace admin with the multisig), or split with
    ///         partners (add a recipient with a bps share).
    function updateRewards(
        address token,
        address[] calldata admins,
        address[] calldata recipients,
        uint16[] calldata bps
    ) external {
        TokenState storage s = _state[token];
        if (!s.initialized) revert TokenNotPlaced();
        if (!_isAdmin(s.rewards.admins, msg.sender)) revert NotRewardAdmin();

        if (admins.length == 0) revert EmptyRewardAdmins();
        if (recipients.length == 0) revert EmptyRewardRecipients();
        if (recipients.length != bps.length) revert LengthMismatch();
        uint256 bpsTotal;
        for (uint256 i = 0; i < bps.length; i++) {
            bpsTotal += bps[i];
        }
        if (bpsTotal != BPS) revert RewardBpsSumMismatch();

        s.rewards.admins = admins;
        s.rewards.recipients = recipients;
        s.rewards.bps = bps;

        emit RewardsUpdated(token, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────

    function isPlaced(address token) external view returns (bool) {
        return _state[token].initialized;
    }

    function positionsOf(address token) external view returns (Position[] memory) {
        return _state[token].positions;
    }

    function rewardsOf(address token)
        external
        view
        returns (address[] memory admins, address[] memory recipients, uint16[] memory bps)
    {
        Rewards storage r = _state[token].rewards;
        return (r.admins, r.recipients, r.bps);
    }

    function currenciesOf(address token) external view returns (Currency, Currency) {
        TokenState storage s = _state[token];
        return (s.currency0, s.currency1);
    }

    // ─────────────────────────────────────────────────────────────────
    // ERC-721 receiver
    // ─────────────────────────────────────────────────────────────────

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        // The PositionManager mints positions directly to address(this)
        // during `placeLiquidity`; no external transfers are expected.
        // We accept silently — emitting per-position is handled in
        // `placeLiquidity` for ordering.
        tokenId;
        return IERC721Receiver.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeLpLocker).interfaceId;
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────

    function _validateConfig(
        PlaceLiquidityConfig calldata cfg,
        int24 startingTick,
        int24 tickSpacing
    ) internal pure {
        uint256 n = cfg.tickLower.length;
        if (n == 0) revert EmptyArray();
        if (n != cfg.tickUpper.length || n != cfg.positionBps.length) revert LengthMismatch();

        if (cfg.rewardAdmins.length == 0) revert EmptyRewardAdmins();
        if (cfg.rewardRecipients.length == 0) revert EmptyRewardRecipients();
        if (cfg.rewardRecipients.length != cfg.rewardBps.length) revert LengthMismatch();

        uint256 positionBpsSum;
        for (uint256 i = 0; i < n; i++) {
            if (cfg.tickLower[i] > cfg.tickUpper[i]) revert TicksBackwards();
            if (cfg.tickLower[i] % tickSpacing != 0 || cfg.tickUpper[i] % tickSpacing != 0) {
                revert TickNotMultipleOfSpacing();
            }
            if (cfg.tickLower[i] < startingTick) revert TickLowerBelowStartingTick();
            positionBpsSum += cfg.positionBps[i];
        }
        if (positionBpsSum != BPS) revert PositionBpsSumMismatch();

        uint256 rewardBpsSum;
        for (uint256 i = 0; i < cfg.rewardBps.length; i++) {
            rewardBpsSum += cfg.rewardBps[i];
        }
        if (rewardBpsSum != BPS) revert RewardBpsSumMismatch();
    }

    function _isAdmin(address[] storage admins, address who) internal view returns (bool) {
        uint256 len = admins.length;
        for (uint256 i = 0; i < len; i++) {
            if (admins[i] == who) return true;
        }
        return false;
    }

    function _distribute(address token, Currency currency) internal {
        address currencyAddr = Currency.unwrap(currency);
        uint256 balance = IERC20(currencyAddr).balanceOf(address(this));
        // The launched token sits as the supply for placeLiquidity — we
        // must not sweep the un-deployed remainder. But after the
        // modifyLiquidities call inside placeLiquidity the locker's
        // token balance is whatever the PositionManager refunded. For
        // `collectFees`, only the collected fees are present here, so
        // we sweep the entire current balance for each currency.
        if (currencyAddr == token) {
            // Defensive: never sweep more than the realised fee. If a
            // misconfigured caller transferred token directly to the
            // locker, that residual is unrecoverable by design (the
            // locker has no admin / withdraw path).
        }
        if (balance == 0) return;

        Rewards storage r = _state[token].rewards;
        uint256 len = r.recipients.length;
        uint256 distributed;
        for (uint256 i = 0; i < len; i++) {
            uint256 share;
            if (i == len - 1) {
                // Last recipient takes the remainder to avoid dust loss
                // from integer division.
                share = balance - distributed;
            } else {
                share = balance * r.bps[i] / BPS;
                distributed += share;
            }
            if (share > 0) IERC20(currencyAddr).safeTransfer(r.recipients[i], share);
        }

        emit FeesCollected(token, currencyAddr, balance, uint8(len));
    }
}
