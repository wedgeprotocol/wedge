// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {Launchpad} from "../src/Launchpad.sol";

/// @notice Step 4 — allowlist the deployed contracts on the Launchpad,
///         set the team-fee recipient, and lift the deprecation flag
///         so `deployToken` can be called.
///
///         Required env:
///         - `LAUNCHPAD`
///         - `MAINLINE_HOOK`
///         - `MEV_MODULE`
///         - `LP_LOCKER`
///         - `RAIL_LOCKER`
///         - `RAIL_EXTENSION`
///         - `TEAM_FEE_RECIPIENT` — protocol treasury (multisig)
contract ConfigureAllowlists is Script {
    function run() external {
        Launchpad launchpad = Launchpad(vm.envAddress("LAUNCHPAD"));
        address mainlineHook = vm.envAddress("MAINLINE_HOOK");
        address mev = vm.envAddress("MEV_MODULE");
        address lpLocker = vm.envAddress("LP_LOCKER");
        address ext = vm.envAddress("RAIL_EXTENSION");
        address treasury = vm.envAddress("TEAM_FEE_RECIPIENT");

        // Note: WedgeRailLocker is *not* allowlisted via setLocker. The
        // Launchpad only knows about Mainline-style lockers (those that
        // implement IWedgeLpLocker.placeLiquidity). The Rail locker
        // receives positions via WedgeRailExtension.safeTransferFrom —
        // its custody role is wired through the extension, which IS
        // allowlisted via setExtension below.
        vm.startBroadcast();
        launchpad.setTeamFeeRecipient(treasury);
        launchpad.setHook(mainlineHook, true);
        launchpad.setMevModule(mev, true);
        launchpad.setLocker(lpLocker, mainlineHook, true);
        launchpad.setExtension(ext, true);
        launchpad.setDeprecated(false);
        vm.stopBroadcast();

        console2.log("Hook allowlisted     :", mainlineHook);
        console2.log("MEV module allowlisted:", mev);
        console2.log("LP locker allowlisted :", lpLocker);
        console2.log("Rail ext allowlisted :", ext);
        console2.log("Treasury             :", treasury);
        console2.log("Launchpad un-deprecated. Ready to deployToken().");
    }
}
