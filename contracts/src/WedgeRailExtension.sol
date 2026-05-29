// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {ILaunchpadProtocolToken} from "./interfaces/ILaunchpadProtocolToken.sol";
import {IWedgeExtension} from "./interfaces/IWedgeExtension.sol";

/// @notice Atomic Rail opener invoked by the Launchpad during a launch.
///         The extension receives 20% of the launched TOKEN supply,
///         reads the WEDGE/WETH Mainline pool's current spot via
///         `getSlot0`, derives the Rail's starting tick so the Rail's
///         implied TOKEN price matches the Mainline's, opens the
///         hookless Rail pool, mints 3 single-sided positions, and
///         safe-transfers the LP NFTs to `WedgeRailLocker`.
///
///         All of this happens inside `Launchpad.deployToken` —
///         minimal delay, no off-chain steps, no oracle dependencies.
///
///         Rail pool shape (per `docs/05 §5`):
///         - Hookless (`hooks = address(0)`)
///         - 0.30% LP fee (3_000 ppm), tick spacing 60
///         - 3 bands seeded one-sided on the TOKEN side, weights
///           [25%, 50%, 25%] of the extension supply (= [5%, 10%, 5%]
///           of total token supply for the default 20% Rail share).
///
///         Tick math: TOKEN/WEDGE price = (TOKEN/WETH) / (WEDGE/WETH).
///         In log-tick space, with all ticks normalised to the
///         "TOKEN-as-currency0" frame (the convention the Launchpad
///         uses for `tickIfToken0IsLaunched`):
///
///             effectiveRailTick = effectiveMainlineTick - effectiveWedgeWethTick
///
///         Then flipped to the Rail pool's actual orientation based on
///         TOKEN vs WEDGE address ordering.
contract WedgeRailExtension is IWedgeExtension {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    string public constant PROTOCOL = "Wedge";

    /// @notice Rail pool LP fee in ppm. 0.30%.
    uint24 public constant RAIL_FEE = 3000;

    /// @notice Rail pool tick spacing for the 0.30% fee tier.
    int24 public constant RAIL_TICK_SPACING = 60;

    /// @notice Position weight within the extension's supply share, in
    ///         bps. The three bands sum to 10_000. Per `docs/05 §6.2`
    ///         (Balanced preset): 5% / 10% / 5% of total supply means
    ///         25% / 50% / 25% within the 20% Rail share.
    uint16 public constant BAND_1_BPS = 2500;
    uint16 public constant BAND_2_BPS = 5000;
    uint16 public constant BAND_3_BPS = 2500;

    /// @notice Tick offsets per band, applied in the "TOKEN cheaper in
    ///         WEDGE = higher effective tick" direction. Multiples of
    ///         60 (Rail tick spacing).
    int24 public constant BAND_1_LOWER_OFFSET = 0;
    int24 public constant BAND_1_UPPER_OFFSET = 10_980;
    int24 public constant BAND_2_LOWER_OFFSET = 6960;
    int24 public constant BAND_2_UPPER_OFFSET = 27_060;
    int24 public constant BAND_3_LOWER_OFFSET = 22_980;
    int24 public constant BAND_3_UPPER_OFFSET = 46_020;

    address public immutable LAUNCHPAD;
    address public immutable RAIL_LOCKER;
    address public immutable WETH;
    address public immutable MAINLINE_HOOK;
    IPoolManager public immutable POOL_MANAGER;
    IPositionManager public immutable POSITION_MANAGER;

    error OnlyLaunchpad();
    error ProtocolTokenNotSet();
    error WedgeWethPoolNotInitialized();
    error RailTickOutOfBounds();

    event RailOpened(
        address indexed token,
        address indexed wedge,
        bytes32 poolId,
        int24 railStartingTick,
        uint256 firstTokenId
    );

    modifier onlyLaunchpad() {
        if (msg.sender != LAUNCHPAD) revert OnlyLaunchpad();
        _;
    }

    constructor(
        address launchpad_,
        address railLocker_,
        address weth_,
        address mainlineHook_,
        address poolManager_,
        address positionManager_
    ) {
        LAUNCHPAD = launchpad_;
        RAIL_LOCKER = railLocker_;
        WETH = weth_;
        MAINLINE_HOOK = mainlineHook_;
        POOL_MANAGER = IPoolManager(poolManager_);
        POSITION_MANAGER = IPositionManager(positionManager_);
    }

    // ─────────────────────────────────────────────────────────────────
    // IWedgeExtension
    // ─────────────────────────────────────────────────────────────────

    function requiresProtocolToken() external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeExtension).interfaceId;
    }

    /// @inheritdoc IWedgeExtension
    function receiveTokens(address token, uint256 extensionSupply, bytes calldata data)
        external
        payable
        onlyLaunchpad
    {
        // The Launchpad's pre-flight already enforced that PROTOCOL_TOKEN
        // is set when this extension is in the deployment, but read
        // defensively in case of allowlist drift.
        address wedge = ILaunchpadProtocolToken(LAUNCHPAD).PROTOCOL_TOKEN();
        if (wedge == address(0)) revert ProtocolTokenNotSet();

        int24 mainlineStartingTick = abi.decode(data, (int24));

        int24 railStartingTick = _computeRailStartingTick(mainlineStartingTick, token, wedge);
        if (railStartingTick < TickMath.MIN_TICK || railStartingTick > TickMath.MAX_TICK) {
            revert RailTickOutOfBounds();
        }

        PoolKey memory railKey = _buildRailKey(token, wedge);

        // Open the Rail pool. `initialize` is callable directly on the
        // PoolManager and returns the tick (which we ignore).
        POOL_MANAGER.initialize(railKey, TickMath.getSqrtPriceAtTick(railStartingTick));

        // Pull TOKEN supply from the Launchpad (already approved in
        // `_triggerExtensions`).
        IERC20(token).safeTransferFrom(LAUNCHPAD, address(this), extensionSupply);
        IERC20(token).forceApprove(address(POSITION_MANAGER), extensionSupply);

        uint256 firstTokenId = POSITION_MANAGER.nextTokenId();
        _mintBands(railKey, railStartingTick, token, wedge, extensionSupply);

        // Hand the three LP NFTs over to the Rail locker. The
        // locker's `onERC721Received` requires `from == _extension`,
        // which is satisfied because this contract initiated the
        // safeTransferFrom.
        bytes memory transferData = abi.encode(token, railKey.currency0, railKey.currency1);
        for (uint256 i = 0; i < 3; i++) {
            IERC721(address(POSITION_MANAGER))
                .safeTransferFrom(address(this), RAIL_LOCKER, firstTokenId + i, transferData);
        }

        emit RailOpened(token, wedge, PoolId.unwrap(railKey.toId()), railStartingTick, firstTokenId);
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal: tick math
    // ─────────────────────────────────────────────────────────────────

    /// @notice Compute the Rail pool's starting tick.
    ///
    ///         The Mainline starting tick passed in is in the
    ///         "TOKEN-as-currency0" convention (positive when TOKEN is
    ///         cheap in WETH at the chosen FDV). The WEDGE/WETH tick
    ///         read from the pool is in the actual pool orientation;
    ///         we flip it to a "WEDGE-as-currency0" convention.
    ///
    ///         In log-tick space (positive = cheaper-in-numeraire):
    ///             effectiveRailTick = effectiveMainlineTick − effectiveWedgeWethTick
    ///
    ///         Then we flip to the Rail pool's actual orientation
    ///         based on TOKEN vs WEDGE address ordering.
    function _computeRailStartingTick(int24 mainlineStartingTick, address token, address wedge)
        internal
        view
        returns (int24 railStartingTick)
    {
        PoolKey memory wedgeWethKey = _buildMainlineKey(wedge, WETH);
        (uint160 sqrtPriceX96, int24 wedgeWethTick,,) = POOL_MANAGER.getSlot0(wedgeWethKey.toId());
        if (sqrtPriceX96 == 0) revert WedgeWethPoolNotInitialized();

        // Normalise WEDGE/WETH tick to "WEDGE-as-currency0" convention.
        // If WEDGE is already currency0 on its pool, the pool tick is
        // already in this convention. Otherwise negate.
        int24 effectiveWedgeWeth = wedge < WETH ? wedgeWethTick : -wedgeWethTick;

        // Both ticks now in the convention "cheap-token-as-currency0".
        // Subtract to get the Rail tick in the "TOKEN-as-currency0" frame.
        int24 effectiveRail = mainlineStartingTick - effectiveWedgeWeth;

        // Apply Rail's actual orientation. When TOKEN < WEDGE, TOKEN is
        // currency0 on the Rail and the pool tick matches the effective
        // frame. When TOKEN > WEDGE, WEDGE is currency0 — pool tick is
        // the negation.
        railStartingTick = token < wedge ? effectiveRail : -effectiveRail;

        // Align to Rail tick spacing toward zero (so the pool can be
        // initialised at exactly this tick — initialize() doesn't
        // require spacing alignment, but the position ticks do, and we
        // want them anchored to the starting tick).
        int24 spacing = RAIL_TICK_SPACING;
        int24 rem = railStartingTick % spacing;
        if (rem != 0) {
            // Round toward zero.
            railStartingTick = railStartingTick - rem;
        }
    }

    function _buildRailKey(address token, address wedge) internal pure returns (PoolKey memory) {
        (address c0, address c1) = token < wedge ? (token, wedge) : (wedge, token);
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: RAIL_FEE,
            tickSpacing: RAIL_TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    function _buildMainlineKey(address t, address paired) internal view returns (PoolKey memory) {
        (address c0, address c1) = t < paired ? (t, paired) : (paired, t);
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(MAINLINE_HOOK)
        });
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal: liquidity placement
    // ─────────────────────────────────────────────────────────────────

    function _mintBands(
        PoolKey memory railKey,
        int24 railStartingTick,
        address token,
        address wedge,
        uint256 extensionSupply
    ) internal {
        bool tokenIsCurrency0 = token < wedge;
        uint16[3] memory bandBps = [BAND_1_BPS, BAND_2_BPS, BAND_3_BPS];
        int24[3] memory lowerOffsets =
            [BAND_1_LOWER_OFFSET, BAND_2_LOWER_OFFSET, BAND_3_LOWER_OFFSET];
        int24[3] memory upperOffsets =
            [BAND_1_UPPER_OFFSET, BAND_2_UPPER_OFFSET, BAND_3_UPPER_OFFSET];

        bytes memory actions = new bytes(4);
        bytes[] memory params = new bytes[](4);

        for (uint256 i = 0; i < 3; i++) {
            (int24 tickLower, int24 tickUpper) =
                _bandTicks(railStartingTick, lowerOffsets[i], upperOffsets[i], tokenIsCurrency0);
            uint256 bandSupply = extensionSupply * bandBps[i] / 10_000;

            uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);
            uint128 liquidity = tokenIsCurrency0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, bandSupply)
                : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, bandSupply);

            actions[i] = bytes1(uint8(Actions.MINT_POSITION));
            params[i] = abi.encode(
                railKey,
                tickLower,
                tickUpper,
                liquidity,
                tokenIsCurrency0 ? uint128(bandSupply) : uint128(0),
                tokenIsCurrency0 ? uint128(0) : uint128(bandSupply),
                address(this),
                bytes("")
            );
        }

        actions[3] = bytes1(uint8(Actions.SETTLE_PAIR));
        params[3] = abi.encode(railKey.currency0, railKey.currency1);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    /// @notice Translate per-band offsets from the "effective" frame
    ///         (positive = TOKEN cheaper in WEDGE) into actual pool
    ///         ticks, depending on which side TOKEN sits on.
    ///
    ///         When TOKEN is currency0: positions are *above* the
    ///         starting tick (offsets applied positively). Single-sided
    ///         TOKEN means the pool price stays at or below tickLower
    ///         until depth at the band is exhausted.
    ///
    ///         When TOKEN is currency1: positions are *below* the
    ///         starting tick (offsets applied negatively, and lower/
    ///         upper swapped so `tickLower < tickUpper` still holds).
    function _bandTicks(
        int24 railStartingTick,
        int24 lowerOffset,
        int24 upperOffset,
        bool tokenIsCurrency0
    ) internal pure returns (int24 tickLower, int24 tickUpper) {
        if (tokenIsCurrency0) {
            tickLower =
                railStartingTick + lowerOffset;
            tickUpper = railStartingTick + upperOffset;
        } else {
            tickLower = railStartingTick - upperOffset;
            tickUpper = railStartingTick - lowerOffset;
        }
    }
}
