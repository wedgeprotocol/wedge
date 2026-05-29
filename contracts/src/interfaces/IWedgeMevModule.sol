// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Optional anti-sniper / MEV-protection module attached to a
///         pool's hook at launch. The hook calls `initialize` once after
///         the pool is created and the LP positions are placed.
interface IWedgeMevModule {
    function initialize(PoolKey calldata poolKey, bytes calldata mevModuleData) external;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
