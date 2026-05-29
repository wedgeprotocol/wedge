// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Minimal swap helper for the fork tests. Calls
///         `PoolManager.swap` inside an unlock callback and settles +
///         takes manually — bypasses the UniversalRouter V4_SWAP
///         plumbing (which isn't in our pinned UR version) while still
///         exercising the full PoolManager → hook (beforeSwap +
///         afterSwap) → settle path.
///
///         Usage:
///             swapper.swap(poolKey, amountIn, zeroForOne, payer, recipient)
///         where `payer` has approved the swapper for `amountIn` of the
///         input currency.
contract TestSwapper is IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable POOL_MANAGER;

    error OnlyPoolManager();

    struct SwapData {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
        address payer;
        address recipient;
    }

    constructor(address poolManager_) {
        POOL_MANAGER = IPoolManager(poolManager_);
    }

    /// @notice Exact-input swap.
    /// @param key Pool to swap in.
    /// @param amountIn Positive — input amount of the `zeroForOne ?
    ///        currency0 : currency1` currency. Translated internally
    ///        to `amountSpecified = -int256(amountIn)`.
    /// @param zeroForOne Direction.
    /// @param payer Address that pays the input — must have approved
    ///        this contract for `amountIn` of the input token.
    /// @param recipient Receives the output.
    function swap(
        PoolKey memory key,
        uint256 amountIn,
        bool zeroForOne,
        address payer,
        address recipient
    ) external returns (BalanceDelta delta) {
        bytes memory result = POOL_MANAGER.unlock(
            abi.encode(
                SwapData({
                    key: key,
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(amountIn),
                    payer: payer,
                    recipient: recipient
                })
            )
        );
        delta = abi.decode(result, (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert OnlyPoolManager();
        SwapData memory s = abi.decode(data, (SwapData));

        BalanceDelta delta = POOL_MANAGER.swap(
            s.key,
            IPoolManager.SwapParams({
                zeroForOne: s.zeroForOne,
                amountSpecified: s.amountSpecified,
                sqrtPriceLimitX96: s.zeroForOne
                    ? uint160(4_295_128_740)
                    : uint160(1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341)
            }),
            ""
        );

        // Settle the input currency: sync, transfer in, then settle so
        // the PoolManager reconciles balance diff → unlocker credit.
        if (delta.amount0() < 0) {
            uint256 owed = uint256(-int256(delta.amount0()));
            POOL_MANAGER.sync(s.key.currency0);
            IERC20(Currency.unwrap(s.key.currency0))
                .safeTransferFrom(s.payer, address(POOL_MANAGER), owed);
            POOL_MANAGER.settle();
        }
        if (delta.amount1() < 0) {
            uint256 owed = uint256(-int256(delta.amount1()));
            POOL_MANAGER.sync(s.key.currency1);
            IERC20(Currency.unwrap(s.key.currency1))
                .safeTransferFrom(s.payer, address(POOL_MANAGER), owed);
            POOL_MANAGER.settle();
        }

        // Take the output currency to recipient.
        if (delta.amount0() > 0) {
            POOL_MANAGER.take(s.key.currency0, s.recipient, uint256(int256(delta.amount0())));
        }
        if (delta.amount1() > 0) {
            POOL_MANAGER.take(s.key.currency1, s.recipient, uint256(int256(delta.amount1())));
        }

        return abi.encode(delta);
    }
}
