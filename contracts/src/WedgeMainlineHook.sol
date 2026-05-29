// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeHook} from "./interfaces/IWedgeHook.sol";
import {IWedgeMevModule} from "./interfaces/IWedgeMevModule.sol";

/// @notice The Mainline pool hook. Handles two fee components per swap:
///
///         **LP fee (base 1.00%)** — paid into the pool's LP positions
///         held by `WedgeLpLocker`, distributed per the locker's
///         `rewardBps` array (default 100% to creator).
///
///         **Hook fee (base 0.20%)** — taken by this contract via
///         `BeforeSwapDelta` / `AfterSwapDelta`, always in the paired
///         currency (WETH on standard launches). Accumulated as ERC-6909
///         balance on the PoolManager, then swept to the Launchpad
///         factory at the start of each subsequent swap. The Launchpad
///         exposes `claimTeamFees(token)` to push from factory → treasury.
///
///         **MEV decay** — the configured `WedgeMevModule` returns an
///         elevated LP fee during the launch window. The hook fee
///         scales proportionally (HOOK_FEE_NUMERATOR = 20% of the
///         active LP fee), preserving the 1.0 / 0.2 creator/protocol
///         split across the decay curve.
///
///         The pool is initialised with the v4 `DYNAMIC_FEE_FLAG` so
///         that the per-swap LP fee override returned from
///         `beforeSwap` is honoured by the PoolManager.
contract WedgeMainlineHook is IWedgeHook, IHooks {
    using LPFeeLibrary for uint24;

    string public constant PROTOCOL = "Wedge";

    /// @notice Base LP fee in ppm (1% = 10_000 ppm). Used when the MEV
    ///         module's decay window has elapsed and it returns 0.
    uint24 public constant BASE_LP_FEE = 10_000;

    /// @notice Hook fee numerator relative to the LP fee, in ppm. With
    ///         this set to 200_000 and the base LP fee at 10_000 ppm,
    ///         the steady-state hook fee is `10_000 × 200_000 / 1_000_000
    ///         = 2_000 ppm = 0.2%`. During MEV decay the hook fee scales
    ///         with the elevated LP fee at the same ratio.
    uint24 public constant HOOK_FEE_NUMERATOR = 200_000;
    uint24 public constant FEE_DENOMINATOR = 1_000_000;

    /// @notice Maximum LP fee the MEV module may set. Anything higher
    ///         is silently clamped to this value when forming the
    ///         override returned to the PoolManager.
    uint24 public constant MAX_MEV_LP_FEE = 999_999;

    address public immutable FACTORY;
    IPoolManager public immutable POOL_MANAGER;

    struct PoolConfig {
        address locker;
        address mevModule;
        bool token0IsLaunched;
        bool initialized;
    }

    mapping(PoolId poolId => PoolConfig config) public pools;

    // OnlyFactory + ETHPoolNotAllowed inherited from IWedgeHook.
    error OnlyPoolManager();
    error PoolAlreadyInitialized();
    error PoolNotInitialized();

    event PoolInitialized(
        PoolId indexed poolId,
        address indexed tokenLaunched,
        address indexed pairedToken,
        int24 startingTick,
        address locker,
        address mevModule
    );
    event HookFeesSwept(PoolId indexed poolId, address indexed currency, uint256 amount);

    modifier onlyFactory() {
        if (msg.sender != FACTORY) revert OnlyFactory();
        _;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert OnlyPoolManager();
        _;
    }

    constructor(address factory_, address poolManager_) {
        FACTORY = factory_;
        POOL_MANAGER = IPoolManager(poolManager_);
    }

    // ─────────────────────────────────────────────────────────────────
    // IWedgeHook — Launchpad-facing
    // ─────────────────────────────────────────────────────────────────

    /// @inheritdoc IWedgeHook
    function initializePool(
        address tokenLaunched,
        address pairedToken,
        int24 tickIfToken0IsLaunched,
        int24 tickSpacing,
        address locker_,
        address mevModule_,
        bytes calldata /* poolData */
    ) external onlyFactory returns (PoolKey memory poolKey) {
        if (tokenLaunched == address(0) || pairedToken == address(0)) {
            revert ETHPoolNotAllowed();
        }

        bool token0IsLaunched_ = tokenLaunched < pairedToken;
        int24 startingTick = token0IsLaunched_ ? tickIfToken0IsLaunched : -tickIfToken0IsLaunched;

        poolKey = PoolKey({
            currency0: Currency.wrap(token0IsLaunched_ ? tokenLaunched : pairedToken),
            currency1: Currency.wrap(token0IsLaunched_ ? pairedToken : tokenLaunched),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });

        PoolId poolId = poolKey.toId();
        if (pools[poolId].initialized) revert PoolAlreadyInitialized();

        pools[poolId] = PoolConfig({
            locker: locker_,
            mevModule: mevModule_,
            token0IsLaunched: token0IsLaunched_,
            initialized: true
        });

        POOL_MANAGER.initialize(poolKey, TickMath.getSqrtPriceAtTick(startingTick));

        emit PoolInitialized(poolId, tokenLaunched, pairedToken, startingTick, locker_, mevModule_);
    }

    /// @inheritdoc IWedgeHook
    function initializeMevModule(PoolKey calldata poolKey, bytes calldata mevModuleData)
        external
        onlyFactory
    {
        PoolConfig memory cfg = pools[poolKey.toId()];
        if (!cfg.initialized) revert PoolNotInitialized();
        IWedgeMevModule(cfg.mevModule).initialize(poolKey, mevModuleData);
    }

    // ─────────────────────────────────────────────────────────────────
    // IHooks — PoolManager-facing
    // ─────────────────────────────────────────────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    /// @notice Per-swap fee composition:
    ///         1. Sweep any accumulated hook fees on the paired currency
    ///            to the factory.
    ///         2. Read the current LP fee from the MEV module. If the
    ///            decay window has elapsed (module returns 0), use the
    ///            base 1% fee instead.
    ///         3. Take the proportional 20% hook fee on the specified
    ///            side via `BeforeSwapDelta`. The remaining two swap
    ///            directions (specified = launched currency) are handled
    ///            in `afterSwap` because the unspecified amount is only
    ///            known after the swap executes.
    function beforeSwap(
        address, /* sender */
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData */
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        PoolConfig memory cfg = pools[key.toId()];

        _sweepHookFees(key, cfg.token0IsLaunched);

        uint24 lpFee = _resolveLpFee(key.toId(), cfg.mevModule);
        uint24 hookFee = uint24(uint256(lpFee) * HOOK_FEE_NUMERATOR / FEE_DENOMINATOR);

        bool swappingForLaunched = params.zeroForOne != cfg.token0IsLaunched;
        bool isExactInput = params.amountSpecified < 0;
        BeforeSwapDelta delta;

        // Case 1: exact-input paired → launched. Specified amount is
        // paired currency. Take hook fee from the specified side.
        if (isExactInput && swappingForLaunched) {
            uint128 scaledFee = uint128(hookFee) * 1e18 / (FEE_DENOMINATOR + hookFee);
            int128 fee = int128(params.amountSpecified * -int128(scaledFee) / 1e18);
            delta = toBeforeSwapDelta(fee, 0);
            _mintHookCredit(_pairedCurrency(key, cfg.token0IsLaunched), uint256(int256(fee)));
        }
        // Case 2: exact-output launched → paired. Specified amount is
        // paired currency (the output the swapper wants). Take hook fee
        // by inflating the specified amount.
        else if (!isExactInput && !swappingForLaunched) {
            uint128 scaledFee = uint128(hookFee) * 1e18 / (FEE_DENOMINATOR - hookFee);
            int128 fee = int128(params.amountSpecified * int128(scaledFee) / 1e18);
            delta = toBeforeSwapDelta(fee, 0);
            _mintHookCredit(_pairedCurrency(key, cfg.token0IsLaunched), uint256(int256(fee)));
        }

        return (IHooks.beforeSwap.selector, delta, lpFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @notice Handles the two swap directions where the unspecified
    ///         currency is the paired one — hook fee is taken from the
    ///         post-swap amounts since they weren't known in beforeSwap.
    function afterSwap(
        address, /* sender */
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData */
    ) external onlyPoolManager returns (bytes4, int128) {
        PoolConfig memory cfg = pools[key.toId()];

        uint24 lpFee = _resolveLpFee(key.toId(), cfg.mevModule);
        uint24 hookFee = uint24(uint256(lpFee) * HOOK_FEE_NUMERATOR / FEE_DENOMINATOR);

        bool swappingForLaunched = params.zeroForOne != cfg.token0IsLaunched;
        bool isExactInput = params.amountSpecified < 0;
        int128 unspecifiedDelta;

        // Case 3: exact-input launched → paired. Take hook fee from
        // the paired amountOut (unspecified, positive).
        if (isExactInput && !swappingForLaunched) {
            int128 amountOut = cfg.token0IsLaunched ? delta.amount1() : delta.amount0();
            unspecifiedDelta = amountOut * int24(hookFee) / int24(FEE_DENOMINATOR);
            _mintHookCredit(
                _pairedCurrency(key, cfg.token0IsLaunched), uint256(int256(unspecifiedDelta))
            );
        }
        // Case 4: exact-output paired → launched. Take hook fee from
        // the paired amountIn (unspecified, negative).
        else if (!isExactInput && swappingForLaunched) {
            int128 amountIn = cfg.token0IsLaunched ? delta.amount1() : delta.amount0();
            unspecifiedDelta = amountIn * -int24(hookFee) / int24(FEE_DENOMINATOR);
            _mintHookCredit(
                _pairedCurrency(key, cfg.token0IsLaunched), uint256(int256(unspecifiedDelta))
            );
        }

        return (IHooks.afterSwap.selector, unspecifiedDelta);
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────

    function _resolveLpFee(PoolId poolId, address mev) internal view returns (uint24) {
        uint24 mevFee = IWedgeMevModule(mev).getFee(poolId);
        if (mevFee == 0) return BASE_LP_FEE;
        if (mevFee > MAX_MEV_LP_FEE) return MAX_MEV_LP_FEE;
        return mevFee;
    }

    function _pairedCurrency(PoolKey calldata key, bool token0IsLaunched_)
        internal
        pure
        returns (Currency)
    {
        return token0IsLaunched_ ? key.currency1 : key.currency0;
    }

    function _mintHookCredit(Currency currency, uint256 amount) internal {
        if (amount == 0) return;
        POOL_MANAGER.mint(address(this), currency.toId(), amount);
    }

    function _sweepHookFees(PoolKey calldata key, bool token0IsLaunched_) internal {
        Currency paired = _pairedCurrency(key, token0IsLaunched_);
        uint256 balance = POOL_MANAGER.balanceOf(address(this), paired.toId());
        if (balance == 0) return;
        POOL_MANAGER.burn(address(this), paired.toId(), balance);
        POOL_MANAGER.take(paired, FACTORY, balance);
        emit HookFeesSwept(key.toId(), Currency.unwrap(paired), balance);
    }

    // ─────────────────────────────────────────────────────────────────
    // Introspection
    // ─────────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeHook).interfaceId;
    }
}
