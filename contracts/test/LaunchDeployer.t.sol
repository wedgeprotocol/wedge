// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {LaunchDeployer} from "../src/LaunchDeployer.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchDeployerHarness {
    /// @dev External wrapper around the library so the library's
    ///      external function is callable via Solidity rather than via
    ///      raw delegatecall in tests.
    function deploy(LaunchDeployer.TokenConfig memory cfg, uint256 supply)
        external
        returns (address)
    {
        return LaunchDeployer.deploy(cfg, supply);
    }
}

contract LaunchDeployerTest is Test {
    LaunchDeployerHarness internal harness;
    address internal admin;

    uint256 internal constant SUPPLY = 100_000_000_000e18;

    function setUp() public {
        harness = new LaunchDeployerHarness();
        admin = makeAddr("admin");
    }

    function _cfg(bytes32 salt) internal view returns (LaunchDeployer.TokenConfig memory) {
        return LaunchDeployer.TokenConfig({
            admin: admin,
            name: "Wedge",
            symbol: "WEDGE",
            salt: salt,
            image: "ipfs://image",
            metadata: "{}",
            context: "ctx",
            renounceAtDeploy: false
        });
    }

    function test_deploy_returns_LaunchToken_with_correct_metadata() public {
        address deployed = harness.deploy(_cfg(bytes32(uint256(1))), SUPPLY);
        LaunchToken token = LaunchToken(deployed);
        assertEq(token.name(), "Wedge");
        assertEq(token.symbol(), "WEDGE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.admin(), admin);
        assertEq(token.originalAdmin(), admin);
        assertEq(token.imageUrl(), "ipfs://image");
        assertEq(token.metadata(), "{}");
        assertEq(token.context(), "ctx");
        assertEq(token.PROTOCOL(), "Wedge");
    }

    function test_deploy_supply_minted_to_harness_caller() public {
        address deployed = harness.deploy(_cfg(bytes32(uint256(2))), SUPPLY);
        // The harness is the immediate caller, so it receives the supply.
        assertEq(LaunchToken(deployed).balanceOf(address(harness)), SUPPLY);
    }

    function test_deploy_same_salt_and_admin_collides() public {
        bytes32 salt = bytes32(uint256(0xc0ffee));
        harness.deploy(_cfg(salt), SUPPLY);
        // Re-deploying with the same (admin, salt) targets the same
        // CREATE2 address; the second call must revert.
        vm.expectRevert();
        harness.deploy(_cfg(salt), SUPPLY);
    }

    function test_deploy_different_salt_returns_different_address() public {
        address a = harness.deploy(_cfg(bytes32(uint256(0xa))), SUPPLY);
        address b = harness.deploy(_cfg(bytes32(uint256(0xb))), SUPPLY);
        assertTrue(a != b);
    }
}
