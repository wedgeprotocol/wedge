// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice MEV-protection module attached to a pool's hook at launch.
///         The hook calls `initialize` once after pool creation. Then
///         on every swap, the hook calls `getFee(poolId)` to obtain the
///         current LP fee (anti-sniper decay schedule). The module
///         returns 0 once the decay window has elapsed — the hook then
///         falls back to the pool's base fee.
interface IWedgeMevModule {
    function initialize(PoolKey calldata poolKey, bytes calldata mevModuleData) external;

    function getFee(PoolId poolId) external view returns (uint24);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
