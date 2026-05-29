// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Interface implemented by every Uniswap v4 hook allowlisted on
///         the Launchpad. The Launchpad calls `initializePool` to open a
///         pool for a newly deployed token and `initializeMevModule` to
///         hand over the active MEV-protection module for that pool.
interface IWedgeHook {
    error ETHPoolNotAllowed();
    error OnlyFactory();
    error UnsupportedInitializePath();

    function initializePool(
        address tokenLaunched,
        address pairedToken,
        int24 tickIfToken0IsLaunched,
        int24 tickSpacing,
        address locker,
        address mevModule,
        bytes calldata poolData
    ) external returns (PoolKey memory);

    function initializeMevModule(PoolKey calldata poolKey, bytes calldata mevModuleData) external;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
