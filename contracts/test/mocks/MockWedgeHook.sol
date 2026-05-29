// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeHook} from "../../src/interfaces/IWedgeHook.sol";

/// @notice Minimal hook stub used by `WedgeMevDescendingFees` tests. It
///         passes `supportsInterface(IWedgeHook)` so the MEV module's
///         hook-interface check accepts it as a legitimate caller.
contract MockWedgeHook {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeHook).interfaceId;
    }
}
