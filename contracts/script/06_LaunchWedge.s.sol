// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {LaunchDeployer} from "../src/LaunchDeployer.sol";
import {Launchpad} from "../src/Launchpad.sol";

import {BaseMainnet} from "./Constants.s.sol";

/// @notice Step 06 — operational. Launches WEDGE through the Launchpad
///         using the Classic Mainline preset (no Rail — WEDGE is the
///         protocol token; pairing it against itself is meaningless),
///         then calls `setProtocolToken(WEDGE)` on the Launchpad so
///         subsequent launches can include the Rail extension.
///
///         Must be run AFTER scripts 00-04 (Launchpad must be live,
///         allowlists must include MainlineHook + LpLocker + Mev
///         module). May be run BEFORE or AFTER step 05 (ownership
///         transfer to multisig). Note that `setProtocolToken` is
///         owner-gated — if step 05 has already run, run this script
///         as the multisig instead.
///
///         Required env:
///         - `LAUNCHPAD`        — from 00
///         - `MAINLINE_HOOK`    — from 01
///         - `LP_LOCKER`        — from 02
///         - `MEV_MODULE`       — from 00
///         - `TREASURY`         — receives WEDGE LP fees (default rewardAdmin/recipient)
///
///         Optional env:
///         - `WEDGE_FDV_TICK`   — Mainline starting tick (TOKEN-as-currency0 frame).
///                                Default 230_200 = ~10 ETH FDV at 100B supply.
///         - `WEDGE_SALT`       — CREATE2 salt for the WEDGE address.
///                                Default keccak256("WEDGE-v1").
///
///         Dev-buy is intentionally NOT part of this script — it's a
///         separate operation that depends on a UniversalRouter swap
///         and treasury-side parameters that are best decided at
///         launch time.
contract LaunchWedge is Script {
    function run() external returns (address wedge) {
        Launchpad launchpad = Launchpad(vm.envAddress("LAUNCHPAD"));
        address mainlineHook = vm.envAddress("MAINLINE_HOOK");
        address lpLocker = vm.envAddress("LP_LOCKER");
        address mev = vm.envAddress("MEV_MODULE");
        address treasury = vm.envAddress("TREASURY");

        int24 startingTick = int24(vm.envOr("WEDGE_FDV_TICK", int256(230_200)));
        bytes32 salt = vm.envOr("WEDGE_SALT", keccak256("WEDGE-v1"));

        Launchpad.DeploymentConfig memory cfg =
            _wedgeConfig(treasury, mainlineHook, lpLocker, mev, startingTick, salt);

        vm.startBroadcast();
        wedge = launchpad.deployToken(cfg);
        launchpad.setProtocolToken(wedge);
        vm.stopBroadcast();

        console2.log("WEDGE deployed at:", wedge);
        console2.log(
            "Launchpad PROTOCOL_TOKEN set. Rail extension is now live for creator launches."
        );
    }

    function _wedgeConfig(
        address treasury,
        address mainlineHook,
        address lpLocker,
        address mev,
        int24 startingTick,
        bytes32 salt
    ) internal pure returns (Launchpad.DeploymentConfig memory cfg) {
        cfg.tokenConfig = LaunchDeployer.TokenConfig({
            admin: treasury,
            name: "Wedge",
            symbol: "WEDGE",
            salt: salt,
            image: "ipfs://placeholder",
            metadata: "{\"description\":\"Wedge Protocol token\"}",
            context: "Wedge - two-pool token launches on Base.",
            renounceAtDeploy: false
        });
        cfg.poolConfig = Launchpad.PoolConfig({
            hook: mainlineHook,
            pairedToken: BaseMainnet.WETH,
            tickIfToken0IsLaunched: startingTick,
            tickSpacing: 200,
            poolData: ""
        });
        cfg.lockerConfig = _fiveBandLockerConfig(lpLocker, treasury, startingTick);
        cfg.mevModuleConfig = Launchpad.MevModuleConfig({
            mevModule: mev,
            mevModuleData: abi.encode(
                uint24(800_000), // startingFee 80%
                uint24(12_000), //  endingFee  1.2%
                uint32(120) //      secondsToDecay
            )
        });
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](0);
    }

    /// @dev Default 5-band Mainline shape per docs/05 §4.1, with the
    ///      starting tick translated to the band offsets.
    function _fiveBandLockerConfig(address lpLocker, address treasury, int24 startingTick)
        internal
        pure
        returns (Launchpad.LockerConfig memory cfg)
    {
        cfg.locker = lpLocker;
        cfg.tickLower = new int24[](5);
        cfg.tickUpper = new int24[](5);
        cfg.positionBps = new uint16[](5);

        // Offsets from the starting tick in ticks-spacing-200 units.
        cfg.tickLower[0] = startingTick;
        cfg.tickUpper[0] = startingTick + 7000;
        cfg.positionBps[0] = 1000;

        cfg.tickLower[1] = startingTick + 4000;
        cfg.tickUpper[1] = startingTick + 21_000;
        cfg.positionBps[1] = 5000;

        cfg.tickLower[2] = startingTick + 16_000;
        cfg.tickUpper[2] = startingTick + 32_000;
        cfg.positionBps[2] = 1500;

        cfg.tickLower[3] = startingTick + 27_000;
        cfg.tickUpper[3] = startingTick + 46_000;
        cfg.positionBps[3] = 2000;

        cfg.tickLower[4] = startingTick + 39_000;
        cfg.tickUpper[4] = startingTick + 62_000;
        cfg.positionBps[4] = 500;

        cfg.rewardAdmins = new address[](1);
        cfg.rewardAdmins[0] = treasury;
        cfg.rewardRecipients = new address[](1);
        cfg.rewardRecipients[0] = treasury;
        cfg.rewardBps = new uint16[](1);
        cfg.rewardBps[0] = 10_000;
    }
}
