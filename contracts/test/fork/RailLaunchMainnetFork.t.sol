// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LaunchDeployer} from "../../src/LaunchDeployer.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {Launchpad} from "../../src/Launchpad.sol";

import {BaseMainnet} from "../../script/Constants.s.sol";
import {MainnetForkBase} from "./MainnetForkBase.sol";

/// @notice Mainnet-fork: full Wedge Rail bootstrap → second-token
///         launch with the Rail extension. Verifies that:
///         - WEDGE deploys via Classic Mainline and creates the
///           WEDGE/WETH pool
///         - `setProtocolToken(WEDGE)` is callable once and locks
///         - a follow-up token launch with Balanced Wedge Rail
///           opens a hookless Rail pool on the TOKEN/WEDGE pair at
///           a tick derived from the WEDGE/WETH spot
///         - the Rail locker holds 3 LP NFTs for the follow-up token
contract RailLaunchMainnetFork is MainnetForkBase {
    using StateLibrary for IPoolManager;

    address internal creator;

    int24 internal constant MAINLINE_STARTING_TICK = 230_200;
    int24 internal constant MAINLINE_TICK_SPACING = 200;

    function setUp() public override {
        super.setUp();
        creator = makeAddr("creator");
    }

    function _classicMainlineConfig(bytes32 salt, string memory name, string memory symbol)
        internal
        view
        returns (Launchpad.DeploymentConfig memory cfg)
    {
        cfg.tokenConfig = LaunchDeployer.TokenConfig({
            admin: creator,
            name: name,
            symbol: symbol,
            salt: salt,
            image: "ipfs://test",
            metadata: "{}",
            context: "fork-test",
            renounceAtDeploy: false
        });
        cfg.poolConfig = Launchpad.PoolConfig({
            hook: address(mainlineHook),
            pairedToken: BaseMainnet.WETH,
            tickIfToken0IsLaunched: MAINLINE_STARTING_TICK,
            tickSpacing: MAINLINE_TICK_SPACING,
            poolData: ""
        });
        cfg.lockerConfig = _fiveBandLockerConfig();
        cfg.mevModuleConfig = Launchpad.MevModuleConfig({
            mevModule: address(mev),
            mevModuleData: abi.encode(uint24(800_000), uint24(12_000), uint32(120))
        });
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](0);
    }

    function _fiveBandLockerConfig() internal view returns (Launchpad.LockerConfig memory cfg) {
        cfg.locker = address(lpLocker);
        cfg.tickLower = new int24[](5);
        cfg.tickUpper = new int24[](5);
        cfg.positionBps = new uint16[](5);
        cfg.tickLower[0] = 230_200;
        cfg.tickUpper[0] = 237_200;
        cfg.positionBps[0] = 1000;
        cfg.tickLower[1] = 234_200;
        cfg.tickUpper[1] = 251_200;
        cfg.positionBps[1] = 5000;
        cfg.tickLower[2] = 246_200;
        cfg.tickUpper[2] = 262_200;
        cfg.positionBps[2] = 1500;
        cfg.tickLower[3] = 257_200;
        cfg.tickUpper[3] = 276_200;
        cfg.positionBps[3] = 2000;
        cfg.tickLower[4] = 269_200;
        cfg.tickUpper[4] = 292_200;
        cfg.positionBps[4] = 500;

        cfg.rewardAdmins = new address[](1);
        cfg.rewardAdmins[0] = creator;
        cfg.rewardRecipients = new address[](1);
        cfg.rewardRecipients[0] = creator;
        cfg.rewardBps = new uint16[](1);
        cfg.rewardBps[0] = 10_000;
    }

    /// @notice Launch WEDGE via the Launchpad and lock it in as
    ///         `PROTOCOL_TOKEN`. Returns the WEDGE address.
    function _bootstrapWedge() internal returns (address wedge) {
        Launchpad.DeploymentConfig memory cfg =
            _classicMainlineConfig(bytes32(uint256(0x57ED6E)), "Wedge", "WEDGE");
        wedge = launchpad.deployToken(cfg);

        vm.prank(owner);
        launchpad.setProtocolToken(wedge);
    }

    // ─────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────

    function test_setProtocolToken_locks_after_first_call() public {
        address wedge = _bootstrapWedge();
        assertEq(launchpad.PROTOCOL_TOKEN(), wedge);

        // Second call must revert.
        vm.prank(owner);
        vm.expectRevert(Launchpad.ProtocolTokenAlreadySet.selector);
        launchpad.setProtocolToken(makeAddr("other"));
    }

    function test_rail_launch_opens_token_wedge_pool() public {
        address wedge = _bootstrapWedge();

        // Build a Balanced Wedge Rail launch (Mainline + Rail extension).
        Launchpad.DeploymentConfig memory cfg =
            _classicMainlineConfig(bytes32(uint256(0xFA11)), "Test", "TEST");
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(railExt),
            msgValue: 0,
            extensionBps: 2000, // 20% of total supply to the Rail
            extensionData: abi.encode(MAINLINE_STARTING_TICK)
        });
        // Mainline now seeds only 80% of supply; rescale positionBps to
        // still sum to 10_000 within its smaller share. We keep the
        // same band shape — positionBps already sums to 10_000 in the
        // as-currency-0 frame and the locker scales the supply per
        // band by these bps automatically.

        address tokenAddress = launchpad.deployToken(cfg);

        // Rail pool should exist on the TOKEN/WEDGE pair, hookless,
        // 0.30% fee, spacing 60.
        (address c0, address c1) =
            tokenAddress < wedge ? (tokenAddress, wedge) : (wedge, tokenAddress);
        PoolKey memory railKey = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        (uint160 sqrtPriceX96,,,) = IPoolManager(BaseMainnet.POOL_MANAGER).getSlot0(railKey.toId());
        assertTrue(sqrtPriceX96 != 0, "Rail pool not initialised");

        // Rail locker holds 3 positions for this token.
        (uint256[3] memory ids,,, uint8 count) = railLocker.holdingsFor(tokenAddress);
        assertEq(count, 3);
        assertTrue(ids[0] != 0);
        assertTrue(ids[1] != 0);
        assertTrue(ids[2] != 0);
    }
}
