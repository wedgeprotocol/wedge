// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice No-op Permit2 stub. Used by unit tests via
///         `vm.etch(PERMIT2_ADDRESS, type(MockPermit2).runtimeCode)`
///         so the production locker/extension contracts can call
///         `IAllowanceTransfer(PERMIT2).approve(...)` without
///         reverting on the canonical Permit2 address (which has
///         no bytecode in non-forked tests).
///
///         Real semantics are exercised in the fork tests, which
///         run against actual mainnet Permit2.
contract MockPermit2 {
    function approve(address, address, uint160, uint48) external {}
}
