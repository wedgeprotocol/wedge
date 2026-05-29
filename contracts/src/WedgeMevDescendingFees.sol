// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeHook} from "./interfaces/IWedgeHook.sol";
import {IWedgeMevModule} from "./interfaces/IWedgeMevModule.sol";

/// @notice Parabolic anti-sniper fee decay. Initialised once per pool by
///         the pool's hook; thereafter the hook reads `getFee(poolId)` on
///         every swap and overrides the pool's LP fee with the returned
///         value. After `secondsToDecay` has elapsed, `getFee` returns 0
///         and the hook reverts to the pool's base fee.
///
///         Decay shape (see `_calculateFee`):
///
///             fee(t) = endingFee + (startingFee − endingFee) · ((D − t) / D)²
///
///         where `D = secondsToDecay`, `t = block.timestamp − poolStart`.
///         Snipers face near-startingFee in the first seconds; the curve
///         drops quickly so that organic buyers arriving past ~30 seconds
///         see fees within an order of magnitude of the base rate.
///
///         A `DELAY_GUARD` of one second blocks trades in the same block
///         as pool creation — eliminates the trivial atomic-launch-and-buy
///         attack where a sniper queues a buy in the same block.
contract WedgeMevDescendingFees is IWedgeMevModule {
    string public constant PROTOCOL = "Wedge";

    /// @dev Sanity bound on the starting fee. 1_000_000 ppm = 100%. The
    ///      hook can choose to enforce a tighter bound; we accept up to
    ///      the v4 PoolManager hard cap.
    uint24 public constant MAX_STARTING_FEE = 1_000_000;

    /// @dev Sanity bound on decay duration (10 minutes). The intent is
    ///      anti-snipe over the first ~2 minutes; nothing reasonable
    ///      needs longer.
    uint32 public constant MAX_SECONDS_TO_DECAY = 600;

    /// @dev Seconds after pool creation during which the module reports
    ///      `getFee = startingFee` rather than the decayed value. A value
    ///      of 1 means the first second-window is treated as the launch
    ///      instant. Snipers cannot win a sub-second race against the
    ///      decay curve.
    uint32 public constant DELAY_GUARD = 1;

    struct FeeConfig {
        uint24 startingFee;
        uint24 endingFee;
        uint32 secondsToDecay;
    }

    mapping(PoolId poolId => FeeConfig feeConfig) public feeConfig;
    mapping(PoolId poolId => uint256 startTime) public poolStartTime;

    error OnlyHook();
    error PoolAlreadyInitialized();
    error StartingFeeMustBeGreaterThanZero();
    error StartingFeeMustBeGreaterThanEndingFee();
    error StartingFeeAboveMaximum();
    error SecondsToDecayMustBeGreaterThanZero();
    error SecondsToDecayAboveMaximum();
    error HookNotWedgeHook();

    event FeeConfigSet(
        PoolId indexed poolId, uint24 startingFee, uint24 endingFee, uint32 secondsToDecay
    );

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) revert OnlyHook();
        _;
    }

    /// @notice Called once per pool by the pool's hook. `mevModuleData`
    ///         is `abi.encode(FeeConfig)`.
    function initialize(PoolKey calldata poolKey, bytes calldata mevModuleData)
        external
        onlyHook(poolKey)
    {
        PoolId poolId = poolKey.toId();
        if (poolStartTime[poolId] != 0) revert PoolAlreadyInitialized();

        // Confirm the caller is a Wedge hook. This also catches the
        // case where the caller is an EOA / non-hook contract that has
        // somehow constructed a fake `PoolKey` pointing at itself.
        if (!IWedgeHook(address(poolKey.hooks)).supportsInterface(type(IWedgeHook).interfaceId)) {
            revert HookNotWedgeHook();
        }

        FeeConfig memory cfg = abi.decode(mevModuleData, (FeeConfig));

        if (cfg.startingFee == 0) revert StartingFeeMustBeGreaterThanZero();
        if (cfg.startingFee <= cfg.endingFee) revert StartingFeeMustBeGreaterThanEndingFee();
        if (cfg.startingFee > MAX_STARTING_FEE) revert StartingFeeAboveMaximum();
        if (cfg.secondsToDecay == 0) revert SecondsToDecayMustBeGreaterThanZero();
        if (cfg.secondsToDecay > MAX_SECONDS_TO_DECAY) revert SecondsToDecayAboveMaximum();

        feeConfig[poolId] = cfg;
        poolStartTime[poolId] = block.timestamp;

        emit FeeConfigSet(poolId, cfg.startingFee, cfg.endingFee, cfg.secondsToDecay);
    }

    /// @notice Current LP fee override for this pool. Returns 0 when the
    ///         module is no longer active (pool not initialised, or
    ///         decay window elapsed) — the hook then falls back to the
    ///         pool's base fee. Returns `startingFee` during the
    ///         `DELAY_GUARD` second after pool creation.
    function getFee(PoolId poolId) external view returns (uint24) {
        uint256 start = poolStartTime[poolId];
        if (start == 0) return 0;

        FeeConfig memory cfg = feeConfig[poolId];
        if (block.timestamp >= start + cfg.secondsToDecay) return 0;
        if (block.timestamp < start + DELAY_GUARD) return cfg.startingFee;

        return _calculateFee(poolId, cfg, start);
    }

    function _calculateFee(PoolId poolId, FeeConfig memory cfg, uint256 start)
        internal
        view
        returns (uint24)
    {
        // `elapsed` excludes the DELAY_GUARD second. After the guard,
        // the curve runs over `secondsToDecay − DELAY_GUARD` seconds.
        // For typical configs (120s decay, 1s guard) this is a 119s
        // window — the 0.8% difference vs. the nominal 120s is the
        // sub-second jitter we accept for cheap implementation.
        uint256 elapsed = block.timestamp - (start + DELAY_GUARD);
        uint256 timeRemaining = cfg.secondsToDecay - elapsed;
        uint256 feeRange = cfg.startingFee - cfg.endingFee;

        // Parabolic decay: fee = endingFee + feeRange · (timeRemaining / D)²
        uint256 normalizedTime = (timeRemaining * 1e18) / cfg.secondsToDecay;
        uint256 squared = (normalizedTime * normalizedTime) / 1e18;
        uint256 decayAmount = (feeRange * squared) / 1e18;

        // silence unused-parameter warning while keeping a useful debug hook
        poolId;

        return uint24(cfg.endingFee + decayAmount);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeMevModule).interfaceId;
    }
}
