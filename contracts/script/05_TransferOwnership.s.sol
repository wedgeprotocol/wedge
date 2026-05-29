// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {Launchpad} from "../src/Launchpad.sol";

/// @notice Step 5 — rotate `Launchpad.owner()` to the protocol's Safe
///         multisig. After this transfer, the EOA used for the deploy
///         can no longer change allowlists, set the treasury, or
///         flip the `deprecated` flag — those are all multisig-gated.
///
///         Required env:
///         - `LAUNCHPAD`        — from 00
///         - `SAFE_MULTISIG`    — the new owner address
///
///         IMPORTANT: this is one-way. Make absolutely sure the
///         Safe address is correct, the signer set is correct, and
///         at least one signer can produce a valid signature. The
///         Launchpad uses OpenZeppelin `Ownable` which has a
///         one-step `transferOwnership` — there is no two-step
///         accept dance.
contract TransferOwnership is Script {
    function run() external {
        Launchpad launchpad = Launchpad(vm.envAddress("LAUNCHPAD"));
        address safe = vm.envAddress("SAFE_MULTISIG");

        require(safe != address(0), "SAFE_MULTISIG is zero");
        require(launchpad.owner() != safe, "already owned by safe");

        vm.startBroadcast();
        launchpad.transferOwnership(safe);
        vm.stopBroadcast();

        require(launchpad.owner() == safe, "ownership transfer failed");
        console2.log("Launchpad owner rotated to:", safe);
    }
}
