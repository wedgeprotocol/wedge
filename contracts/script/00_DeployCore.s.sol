// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {Launchpad} from "../src/Launchpad.sol";
import {WedgeMevDescendingFees} from "../src/WedgeMevDescendingFees.sol";

/// @notice Step 0 — deploy the dep-free core contracts.
///
///         Deploys:
///         - Launchpad (factory, owner = `OWNER` env var)
///         - WedgeMevDescendingFees (no constructor args)
///
///         Output: the deployed addresses logged to stdout. Capture
///         them in `deployments/<chain>.json` for use by 01–04.
///
///         Run: `forge script script/00_DeployCore.s.sol --rpc-url $BASE_RPC_URL --broadcast`
contract DeployCore is Script {
    function run() external returns (Launchpad launchpad, WedgeMevDescendingFees mev) {
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();
        launchpad = new Launchpad(owner);
        mev = new WedgeMevDescendingFees();
        vm.stopBroadcast();

        console2.log("Launchpad             :", address(launchpad));
        console2.log("WedgeMevDescendingFees:", address(mev));
        console2.log("Owner                 :", owner);
    }
}
