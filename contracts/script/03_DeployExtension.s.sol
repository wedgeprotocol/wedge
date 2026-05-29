// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {WedgeRailExtension} from "../src/WedgeRailExtension.sol";
import {WedgeRailLocker} from "../src/WedgeRailLocker.sol";

import {BaseMainnet} from "./Constants.s.sol";

/// @notice Step 3 — deploy the Rail extension and wire the Rail locker.
///
///         Required env:
///         - `LAUNCHPAD`         — from 00
///         - `RAIL_LOCKER`       — from 02
///         - `MAINLINE_HOOK`     — from 01
///
///         After deploy, calls `RailLocker.setExtension(extension)`
///         from the same EOA that deployed the locker (the deployer).
///         If the deployer key is different from the one used in 02,
///         this script will revert with `NotBootstrap`.
contract DeployExtension is Script {
    function run() external returns (WedgeRailExtension ext) {
        address launchpad = vm.envAddress("LAUNCHPAD");
        address railLocker = vm.envAddress("RAIL_LOCKER");
        address mainlineHook = vm.envAddress("MAINLINE_HOOK");

        vm.startBroadcast();
        ext = new WedgeRailExtension(
            launchpad,
            railLocker,
            BaseMainnet.WETH,
            mainlineHook,
            BaseMainnet.POOL_MANAGER,
            BaseMainnet.POSITION_MANAGER
        );
        WedgeRailLocker(railLocker).setExtension(address(ext));
        vm.stopBroadcast();

        console2.log("WedgeRailExtension:", address(ext));
        console2.log("Locker wired to ext via setExtension");
    }
}
