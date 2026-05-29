// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

import {WedgeMainlineHook} from "../src/WedgeMainlineHook.sol";

import {BaseMainnet} from "./Constants.s.sol";

/// @notice Step 1 — mine + deploy the Mainline hook at an address with
///         the required v4 permission bits.
///
///         Required flags (low 14 bits of address):
///         - BEFORE_SWAP_FLAG (1 << 7)
///         - AFTER_SWAP_FLAG (1 << 6)
///         - BEFORE_SWAP_RETURNS_DELTA_FLAG (1 << 3)
///         - AFTER_SWAP_RETURNS_DELTA_FLAG (1 << 2)
///         Combined: 0xCC.
///
///         Required env: `LAUNCHPAD` (the address from 00).
///
///         Output: hook address (predictably derivable from the
///         CREATE2 salt) + the mined salt.
contract DeployHook is Script {
    function run() external returns (WedgeMainlineHook hook, bytes32 salt) {
        address launchpad = vm.envAddress("LAUNCHPAD");

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(launchpad, BaseMainnet.POOL_MANAGER);

        (address minedAddress, bytes32 minedSalt) = HookMiner.find(
            BaseMainnet.CREATE2_DEPLOYER,
            flags,
            type(WedgeMainlineHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast();
        hook = new WedgeMainlineHook{salt: minedSalt}(launchpad, BaseMainnet.POOL_MANAGER);
        vm.stopBroadcast();

        require(address(hook) == minedAddress, "Hook address mismatch");
        salt = minedSalt;

        console2.log("WedgeMainlineHook:", address(hook));
        console2.log("Salt             :", vm.toString(salt));
    }
}
