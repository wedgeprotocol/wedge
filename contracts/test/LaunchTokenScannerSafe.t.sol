// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {LaunchToken} from "../src/LaunchToken.sol";

/// @notice Asserts the LaunchToken bytecode has no function selectors
///         for any of the operations TokenSniffer / GoPlus / DEXTools
///         routinely flag as red. Catches regressions where a future
///         change accidentally re-introduces an inflation or admin-
///         mint surface that would tank the scanner score.
///
///         The check is `address(token).code` byte search for the
///         4-byte selector — robust against renames since we hash the
///         well-known signatures.
contract LaunchTokenScannerSafeTest is Test {
    LaunchToken internal token;

    function setUp() public {
        token = new LaunchToken({
            name_: "Wedge",
            symbol_: "WEDGE",
            maxSupply_: 100_000_000_000e18,
            admin_: address(this),
            image_: "ipfs://test",
            metadata_: "{}",
            context_: "test",
            renounceAtDeploy_: false
        });
    }

    function _assertNoSelector(string memory signature) internal view {
        bytes4 sel = bytes4(keccak256(bytes(signature)));
        bytes memory code = address(token).code;
        for (uint256 i = 0; i < code.length - 3; i++) {
            require(
                !(code[i] == sel[0] && code[i + 1] == sel[1] && code[i + 2] == sel[2]
                        && code[i + 3] == sel[3]),
                string.concat("Scanner-flagged selector present: ", signature)
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Inflation / mint surfaces
    // ─────────────────────────────────────────────────────────────────

    function test_no_mint_selector() public view {
        _assertNoSelector("mint(address,uint256)");
        _assertNoSelector("mint(uint256)");
        _assertNoSelector("mintTo(address,uint256)");
    }

    function test_no_crosschain_mint_burn_selectors() public view {
        _assertNoSelector("crosschainMint(address,uint256)");
        _assertNoSelector("crosschainBurn(address,uint256)");
    }

    function test_no_mint_rate_or_inflation_setters() public view {
        _assertNoSelector("updateMintRate(uint256)");
        _assertNoSelector("setMintRate(uint256)");
        _assertNoSelector("mintInflation(uint256)");
        _assertNoSelector("inflate(uint256)");
    }

    function test_no_factory_mint_selector() public view {
        _assertNoSelector("factoryMint(address,uint256)");
    }

    // ─────────────────────────────────────────────────────────────────
    // Pause / blacklist / freeze
    // ─────────────────────────────────────────────────────────────────

    function test_no_pause_unpause_selectors() public view {
        _assertNoSelector("pause()");
        _assertNoSelector("unpause()");
        _assertNoSelector("paused()");
    }

    function test_no_blacklist_selectors() public view {
        _assertNoSelector("blacklist(address)");
        _assertNoSelector("unBlacklist(address)");
        _assertNoSelector("blacklisted(address)");
        _assertNoSelector("setBlacklist(address,bool)");
    }

    function test_no_freeze_unfreeze_selectors() public view {
        _assertNoSelector("freeze(address)");
        _assertNoSelector("unfreeze(address)");
        _assertNoSelector("frozen(address)");
    }

    // ─────────────────────────────────────────────────────────────────
    // Pool lock / fee manipulation
    // ─────────────────────────────────────────────────────────────────

    function test_no_pool_lock_unlock_selectors() public view {
        _assertNoSelector("lockPool(address)");
        _assertNoSelector("unlockPool(address)");
        _assertNoSelector("setPoolLocked(address,bool)");
    }

    function test_no_fee_setter_selectors() public view {
        _assertNoSelector("setFee(uint256)");
        _assertNoSelector("setTaxFee(uint256)");
        _assertNoSelector("setBuyFee(uint256)");
        _assertNoSelector("setSellFee(uint256)");
    }

    // ─────────────────────────────────────────────────────────────────
    // Sanity: selectors that SHOULD be present
    // ─────────────────────────────────────────────────────────────────

    function test_has_expected_admin_selectors() public {
        bytes4 sel = bytes4(keccak256("updateAdmin(address)"));
        bytes memory code = address(token).code;
        bool found = _containsSelector(code, sel);
        assertTrue(found, "updateAdmin selector should be present");

        sel = bytes4(keccak256("renounceAdmin()"));
        found = _containsSelector(code, sel);
        assertTrue(found, "renounceAdmin selector should be present");

        sel = bytes4(keccak256("updateImage(string)"));
        found = _containsSelector(code, sel);
        assertTrue(found, "updateImage selector should be present");

        sel = bytes4(keccak256("updateMetadata(string)"));
        found = _containsSelector(code, sel);
        assertTrue(found, "updateMetadata selector should be present");

        sel = bytes4(keccak256("verify()"));
        found = _containsSelector(code, sel);
        assertTrue(found, "verify selector should be present");
    }

    function _containsSelector(bytes memory code, bytes4 sel) internal pure returns (bool) {
        for (uint256 i = 0; i < code.length - 3; i++) {
            if (
                code[i] == sel[0] && code[i + 1] == sel[1] && code[i + 2] == sel[2]
                    && code[i + 3] == sel[3]
            ) return true;
        }
        return false;
    }
}
