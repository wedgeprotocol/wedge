// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LaunchToken} from "../src/LaunchToken.sol";
import {Test} from "forge-std/Test.sol";

contract LaunchTokenTest is Test {
    LaunchToken internal token;
    address internal deployer;
    address internal admin;
    address internal alice;
    address internal bob;

    uint256 internal constant SUPPLY = 100_000_000_000e18; // 100B with 18 decimals

    event UpdateAdmin(address indexed oldAdmin, address indexed newAdmin);
    event UpdateImage(string image);
    event UpdateMetadata(string metadata);
    event AdminRenounced(address indexed previousAdmin);
    event Verified(address indexed admin, address indexed token);

    function setUp() public {
        deployer = address(this);
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new LaunchToken({
            name_: "Wedge",
            symbol_: "WEDGE",
            maxSupply_: SUPPLY,
            admin_: admin,
            image_: "ipfs://image",
            metadata_: "{\"description\":\"initial\"}",
            context_: "context-blob"
        });
    }

    // -------------------------------------------------------------------------
    // Supply & basics
    // -------------------------------------------------------------------------

    function test_token_supply_is_100B_on_deploy() public view {
        assertEq(token.totalSupply(), SUPPLY);
        // Supply is minted to msg.sender of the constructor (the test contract).
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_token_decimals_is_18() public view {
        assertEq(token.decimals(), 18);
    }

    function test_token_burn_succeeds_for_holder() public {
        assertTrue(token.transfer(alice, 1000e18));
        vm.prank(alice);
        token.burn(400e18);
        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.totalSupply(), SUPPLY - 400e18);
    }

    function test_token_permit_signature_works() public {
        uint256 ownerKey = 0xA11CE;
        address owner = vm.addr(ownerKey);
        assertTrue(token.transfer(owner, 1000e18));

        uint256 nonce = token.nonces(owner);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 250e18;

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash =
            keccak256(abi.encode(permitTypehash, owner, alice, value, nonce, deadline));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        token.permit(owner, alice, value, deadline, v, r, s);
        assertEq(token.allowance(owner, alice), value);
        assertEq(token.nonces(owner), nonce + 1);
    }

    function test_token_votes_delegate_works() public {
        assertTrue(token.transfer(alice, 5000e18));
        vm.prank(alice);
        token.delegate(bob);
        // Votes accrue at the next block.
        vm.roll(block.number + 1);
        assertEq(token.getVotes(bob), 5000e18);
        assertEq(token.delegates(alice), bob);
    }

    // -------------------------------------------------------------------------
    // Admin lifecycle — pre-renounce
    // -------------------------------------------------------------------------

    function test_token_admin_initially_set_to_constructor_arg() public view {
        assertEq(token.admin(), admin);
    }

    function test_token_originalAdmin_immutable() public {
        assertEq(token.originalAdmin(), admin);
        // After rotation, originalAdmin still equals the constructor admin.
        vm.prank(admin);
        token.updateAdmin(alice);
        assertEq(token.originalAdmin(), admin);
        assertEq(token.admin(), alice);
    }

    function test_token_admin_can_be_rotated_by_admin() public {
        vm.prank(admin);
        token.updateAdmin(alice);
        assertEq(token.admin(), alice);

        vm.prank(alice);
        token.updateAdmin(bob);
        assertEq(token.admin(), bob);
    }

    function test_token_admin_rotation_only_by_current_admin() public {
        vm.prank(alice);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateAdmin(bob);
    }

    function test_token_image_can_be_updated_by_admin() public {
        vm.prank(admin);
        token.updateImage("ipfs://new-image");
        assertEq(token.imageUrl(), "ipfs://new-image");
    }

    function test_token_metadata_can_be_updated_by_admin() public {
        vm.prank(admin);
        token.updateMetadata("{\"description\":\"updated\"}");
        assertEq(token.metadata(), "{\"description\":\"updated\"}");
    }

    function test_token_image_update_only_by_current_admin() public {
        vm.prank(alice);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateImage("ipfs://phishing");
    }

    function test_token_metadata_update_only_by_current_admin() public {
        vm.prank(alice);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateMetadata("malicious");
    }

    function test_token_emits_UpdateAdmin_UpdateImage_UpdateMetadata() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true, address(token));
        emit UpdateAdmin(admin, alice);
        token.updateAdmin(alice);

        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectEmit(false, false, false, true, address(token));
        emit UpdateImage("ipfs://new");
        token.updateImage("ipfs://new");

        vm.expectEmit(false, false, false, true, address(token));
        emit UpdateMetadata("new-meta");
        token.updateMetadata("new-meta");

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Renounce path
    // -------------------------------------------------------------------------

    function test_token_renounce_clears_admin() public {
        vm.prank(admin);
        token.renounceAdmin();
        assertEq(token.admin(), address(0));
    }

    function test_token_renounce_only_by_current_admin() public {
        vm.prank(alice);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.renounceAdmin();
    }

    function test_token_renounce_emits_AdminRenounced() public {
        vm.expectEmit(true, false, false, true, address(token));
        emit AdminRenounced(admin);
        vm.prank(admin);
        token.renounceAdmin();
    }

    function test_token_renounce_idempotent_reverts() public {
        vm.prank(admin);
        token.renounceAdmin();
        // Original admin no longer matches `_admin` (which is now 0).
        vm.prank(admin);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.renounceAdmin();
    }

    function test_token_updateAdmin_reverts_after_renounce() public {
        vm.prank(admin);
        token.renounceAdmin();

        vm.prank(admin);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateAdmin(alice);
    }

    function test_token_updateImage_reverts_after_renounce() public {
        vm.prank(admin);
        token.renounceAdmin();

        vm.prank(admin);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateImage("ipfs://anything");
    }

    function test_token_updateMetadata_reverts_after_renounce() public {
        vm.prank(admin);
        token.renounceAdmin();

        vm.prank(admin);
        vm.expectRevert(LaunchToken.NotAdmin.selector);
        token.updateMetadata("anything");
    }

    // -------------------------------------------------------------------------
    // Verify (one-shot signal)
    // -------------------------------------------------------------------------

    function test_token_verify_callable_once_by_originalAdmin() public {
        assertFalse(token.isVerified());
        vm.expectEmit(true, true, false, true, address(token));
        emit Verified(admin, address(token));
        vm.prank(admin);
        token.verify();
        assertTrue(token.isVerified());
    }

    function test_token_verify_second_call_reverts() public {
        vm.prank(admin);
        token.verify();
        vm.prank(admin);
        vm.expectRevert(LaunchToken.AlreadyVerified.selector);
        token.verify();
    }

    function test_token_verify_only_by_originalAdmin_even_after_rotation() public {
        vm.prank(admin);
        token.updateAdmin(alice);

        // Alice is now the admin, but verify() is gated to _originalAdmin (= the constructor admin).
        vm.prank(alice);
        vm.expectRevert(LaunchToken.NotOriginalAdmin.selector);
        token.verify();

        // The original admin can still call verify(), even though _admin was rotated.
        vm.prank(admin);
        token.verify();
        assertTrue(token.isVerified());
    }

    // -------------------------------------------------------------------------
    // Scanner-safe surface (ABI introspection)
    // -------------------------------------------------------------------------

    /// @dev `address(token).call(abi.encodeWithSelector(sel))` returns ok=false when
    ///      the selector is not present in the contract's ABI dispatch table.
    function _selectorPresent(bytes4 sel) internal returns (bool) {
        (bool ok,) = address(token).call(abi.encodeWithSelector(sel));
        return ok;
    }

    function test_token_has_no_crosschain_functions() public {
        // crosschainMint(address,uint256) and crosschainBurn(address,uint256)
        assertFalse(_selectorPresent(bytes4(keccak256("crosschainMint(address,uint256)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("crosschainBurn(address,uint256)"))));
    }

    function test_token_has_no_mint_after_construction() public {
        // Total supply is fixed in the constructor; no public mint selector exists.
        assertFalse(_selectorPresent(bytes4(keccak256("mint(address,uint256)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("mint(uint256)"))));
    }

    function test_token_has_no_inflation_functions() public {
        // No inflation controls.
        assertFalse(_selectorPresent(bytes4(keccak256("updateMintRate(uint256)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("mintInflation()"))));
    }

    function test_token_has_no_pool_controls() public {
        // The token has no pool-control surface; pools are owned by lockers, not the token.
        assertFalse(_selectorPresent(bytes4(keccak256("lockPool(address)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("unlockPool()"))));
    }

    function test_token_has_no_blacklist_or_pause() public {
        assertFalse(_selectorPresent(bytes4(keccak256("addToBlacklist(address)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("removeFromBlacklist(address)"))));
        assertFalse(_selectorPresent(bytes4(keccak256("pause()"))));
        assertFalse(_selectorPresent(bytes4(keccak256("unpause()"))));
        assertFalse(_selectorPresent(bytes4(keccak256("setSlippage(uint256)"))));
    }
}
