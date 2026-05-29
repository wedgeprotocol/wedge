// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Custodian for a launched token's LP NFT(s). The Launchpad
///         transfers the token-side liquidity in via approval and asks
///         the locker to mint and hold the V4 positions. Reward
///         recipients claim accrued LP fees through the locker; no path
///         exists to recover the underlying positions.
interface IWedgeLpLocker {
    struct PlaceLiquidityConfig {
        address[] rewardAdmins;
        address[] rewardRecipients;
        uint16[] rewardBps;
        int24[] tickLower;
        int24[] tickUpper;
        uint16[] positionBps;
        bytes lockerData;
    }

    function placeLiquidity(
        PlaceLiquidityConfig calldata config,
        PoolKey calldata poolKey,
        int24 startingTick,
        int24 tickSpacing,
        uint256 poolSupply,
        address token
    ) external returns (uint256 positionId);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
