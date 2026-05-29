// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

import {Launchpad} from "../../src/Launchpad.sol";
import {WedgeLpLocker} from "../../src/WedgeLpLocker.sol";
import {WedgeMainlineHook} from "../../src/WedgeMainlineHook.sol";
import {WedgeMevDescendingFees} from "../../src/WedgeMevDescendingFees.sol";
import {WedgeRailExtension} from "../../src/WedgeRailExtension.sol";
import {WedgeRailLocker} from "../../src/WedgeRailLocker.sol";

import {BaseMainnet} from "../../script/Constants.s.sol";

/// @notice Shared scaffolding for Base mainnet-fork integration tests.
///         Forks Base at a recent block, deploys the full Phase 1
///         contract set, wires the allowlists, and lifts the
///         `deprecated` flag — leaving the Launchpad in the same
///         state it would be in after running the 00-04 deploy
///         scripts.
///
///         Tests that need the protocol-token (Rail) flow must
///         additionally launch a "WEDGE" token first and call
///         `Launchpad.setProtocolToken(...)`.
///
///         Skipped automatically when `BASE_RPC_URL` is not set, so
///         the unit-test workflow doesn't fail when the secret is
///         absent.
abstract contract MainnetForkBase is Test {
    Launchpad internal launchpad;
    WedgeMevDescendingFees internal mev;
    WedgeMainlineHook internal mainlineHook;
    WedgeLpLocker internal lpLocker;
    WedgeRailLocker internal railLocker;
    WedgeRailExtension internal railExt;

    address internal owner;
    address internal treasury;
    address internal deployer;

    function _forkOrSkip() internal {
        try vm.envString("BASE_RPC_URL") returns (string memory url) {
            uint256 forkId = vm.createFork(url);
            vm.selectFork(forkId);
        } catch {
            vm.skip(true);
        }
    }

    function setUp() public virtual {
        _forkOrSkip();

        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        deployer = address(this); // tests deploy contracts directly

        // Step 00: Launchpad + MEV module
        launchpad = new Launchpad(owner);
        mev = new WedgeMevDescendingFees();

        // Step 01: mine + deploy the Mainline hook
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(address(launchpad), BaseMainnet.POOL_MANAGER);
        (address minedAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(WedgeMainlineHook).creationCode, ctorArgs);
        mainlineHook =
            new WedgeMainlineHook{salt: salt}(address(launchpad), BaseMainnet.POOL_MANAGER);
        require(address(mainlineHook) == minedAddress, "hook addr mismatch");

        // Step 02: lockers
        lpLocker = new WedgeLpLocker(address(launchpad), BaseMainnet.POSITION_MANAGER);
        railLocker = new WedgeRailLocker(address(launchpad), BaseMainnet.POSITION_MANAGER);

        // Step 03: Rail extension + setExtension wiring
        railExt = new WedgeRailExtension(
            address(launchpad),
            address(railLocker),
            BaseMainnet.WETH,
            address(mainlineHook),
            BaseMainnet.POOL_MANAGER,
            BaseMainnet.POSITION_MANAGER
        );
        railLocker.setExtension(address(railExt));

        // Step 04: allowlists + treasury + un-deprecate (as owner)
        vm.startPrank(owner);
        launchpad.setTeamFeeRecipient(treasury);
        launchpad.setHook(address(mainlineHook), true);
        launchpad.setMevModule(address(mev), true);
        launchpad.setLocker(address(lpLocker), address(mainlineHook), true);
        // Rail locker is NOT allowlisted here — it's a NFT custodian
        // invoked by the Rail extension, not by the Launchpad's
        // locker.placeLiquidity path.
        launchpad.setExtension(address(railExt), true);
        launchpad.setDeprecated(false);
        vm.stopPrank();
    }
}
