// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Smoke test that verifies the Foundry toolchain is wired correctly.
///         Deleted as soon as the first real contract test lands in Phase 1.2.
contract SanityTest is Test {
    function test_toolchain_works() public pure {
        assertEq(uint256(1) + uint256(1), uint256(2));
    }
}
