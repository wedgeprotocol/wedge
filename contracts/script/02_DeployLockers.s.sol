// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {WedgeLpLocker} from "../src/WedgeLpLocker.sol";
import {WedgeRailLocker} from "../src/WedgeRailLocker.sol";

import {BaseMainnet} from "./Constants.s.sol";

/// @notice Step 2 — deploy both lockers.
///
///         Required env: `LAUNCHPAD`.
///
///         Note: WedgeRailLocker.setExtension is called in step 03,
///         after WedgeRailExtension is deployed.
contract DeployLockers is Script {
    function run() external returns (WedgeLpLocker lpLocker, WedgeRailLocker railLocker) {
        address launchpad = vm.envAddress("LAUNCHPAD");

        vm.startBroadcast();
        lpLocker = new WedgeLpLocker(launchpad, BaseMainnet.POSITION_MANAGER);
        railLocker = new WedgeRailLocker(launchpad, BaseMainnet.POSITION_MANAGER);
        vm.stopBroadcast();

        console2.log("WedgeLpLocker  :", address(lpLocker));
        console2.log("WedgeRailLocker:", address(railLocker));
    }
}
