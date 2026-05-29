// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LaunchDeployer} from "../../src/LaunchDeployer.sol";
import {Launchpad} from "../../src/Launchpad.sol";

import {BaseMainnet} from "../../script/Constants.s.sol";
import {MainnetForkBase} from "./MainnetForkBase.sol";
import {TestSwapper} from "./helpers/TestSwapper.sol";

/// @notice Mainnet-fork: full fee round-trip.
///         1. Launch a token (Classic Mainline).
///         2. Snipe-swap (heavy fee window) → hook accumulates ERC-6909.
///         3. Second swap → hook's beforeSwap sweeps prior fee to factory.
///         4. claimTeamFees → factory pushes WETH to treasury.
///         5. (Optional) collectFees on LP locker → creator gets LP fees.
contract FeeFlowMainnetFork is MainnetForkBase {
    TestSwapper internal swapper;

    address internal creator;
    address internal buyer;

    int24 internal constant STARTING_TICK = 230_200;
    int24 internal constant TICK_SPACING = 200;

    function setUp() public override {
        super.setUp();
        creator = makeAddr("creator");
        buyer = makeAddr("buyer");
        swapper = new TestSwapper(BaseMainnet.POOL_MANAGER);
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

    function _launch(bytes32 salt) internal returns (address tokenAddress, PoolKey memory key) {
        Launchpad.DeploymentConfig memory cfg;
        cfg.tokenConfig = LaunchDeployer.TokenConfig({
            admin: creator,
            name: "Fee Test",
            symbol: "FEE",
            salt: salt,
            image: "ipfs://test",
            metadata: "{}",
            context: "fork-test",
            renounceAtDeploy: false
        });
        cfg.poolConfig = Launchpad.PoolConfig({
            hook: address(mainlineHook),
            pairedToken: BaseMainnet.WETH,
            tickIfToken0IsLaunched: STARTING_TICK,
            tickSpacing: TICK_SPACING,
            poolData: ""
        });
        cfg.lockerConfig = _fiveBandLockerConfig();
        cfg.mevModuleConfig = Launchpad.MevModuleConfig({
            mevModule: address(mev),
            mevModuleData: abi.encode(uint24(800_000), uint24(12_000), uint32(120))
        });
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](0);

        tokenAddress = launchpad.deployToken(cfg);

        bool token0IsLaunched = tokenAddress < BaseMainnet.WETH;
        key = PoolKey({
            currency0: Currency.wrap(token0IsLaunched ? tokenAddress : BaseMainnet.WETH),
            currency1: Currency.wrap(token0IsLaunched ? BaseMainnet.WETH : tokenAddress),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(mainlineHook))
        });
    }

    function _buy(PoolKey memory key, uint256 wethIn) internal {
        deal(BaseMainnet.WETH, buyer, wethIn);
        vm.prank(buyer);
        IERC20(BaseMainnet.WETH).approve(address(swapper), wethIn);
        bool zeroForOne = Currency.unwrap(key.currency0) == BaseMainnet.WETH;
        vm.prank(buyer);
        swapper.swap(key, wethIn, zeroForOne, buyer, buyer);
    }

    // ─────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────

    function test_hook_fee_sweeps_to_factory_on_next_swap() public {
        (, PoolKey memory key) = _launch(bytes32(uint256(1)));

        uint256 factoryWethBefore = IERC20(BaseMainnet.WETH).balanceOf(address(launchpad));
        assertEq(factoryWethBefore, 0, "factory should start with 0 WETH");

        // Snipe buy at t=0 — hook accumulates fee as ERC-6909.
        _buy(key, 0.01 ether);

        // After the first swap, fee sits as 6909 on the hook (not yet
        // swept to factory). Factory still has 0 WETH in this state.
        // Sweep happens in the NEXT beforeSwap.
        assertEq(
            IERC20(BaseMainnet.WETH).balanceOf(address(launchpad)),
            0,
            "factory should still have 0 WETH after first swap"
        );

        // Second swap: hook's beforeSwap sweeps the prior fee to factory.
        vm.warp(block.timestamp + 121); // past decay so we know base fees apply
        _buy(key, 0.01 ether);

        uint256 factoryWethAfter = IERC20(BaseMainnet.WETH).balanceOf(address(launchpad));
        assertTrue(factoryWethAfter > 0, "factory should hold swept hook fees");
    }

    function test_claimTeamFees_pushes_to_treasury() public {
        (address tokenAddress, PoolKey memory key) = _launch(bytes32(uint256(2)));

        // Two swaps so the second sweeps the first's fee to factory.
        _buy(key, 0.01 ether);
        vm.warp(block.timestamp + 121);
        _buy(key, 0.01 ether);

        uint256 factoryWeth = IERC20(BaseMainnet.WETH).balanceOf(address(launchpad));
        assertTrue(factoryWeth > 0, "factory should have WETH");

        uint256 treasuryWethBefore = IERC20(BaseMainnet.WETH).balanceOf(treasury);

        // claimTeamFees pushes the WETH from the factory to teamFeeRecipient.
        vm.prank(owner);
        launchpad.claimTeamFees(BaseMainnet.WETH);

        uint256 treasuryWethAfter = IERC20(BaseMainnet.WETH).balanceOf(treasury);
        assertEq(treasuryWethAfter - treasuryWethBefore, factoryWeth);
        assertEq(IERC20(BaseMainnet.WETH).balanceOf(address(launchpad)), 0);

        // Silence unused-variable.
        tokenAddress;
    }

    function test_locker_collectFees_distributes_to_creator() public {
        (address tokenAddress, PoolKey memory key) = _launch(bytes32(uint256(3)));

        // Snipe + post-decay swap so LP positions accrue fees.
        _buy(key, 0.01 ether);
        vm.warp(block.timestamp + 121);
        _buy(key, 0.01 ether);

        uint256 creatorWethBefore = IERC20(BaseMainnet.WETH).balanceOf(creator);
        uint256 creatorTokenBefore = IERC20(tokenAddress).balanceOf(creator);

        // collectFees is permissionless.
        vm.prank(makeAddr("anyone"));
        lpLocker.collectFees(tokenAddress);

        // Creator should have received some WETH (the LP-side fee from
        // the buys). The exact amount depends on tick math; assert > 0.
        assertTrue(
            IERC20(BaseMainnet.WETH).balanceOf(creator) > creatorWethBefore,
            "creator received no WETH fees"
        );
        // The TOKEN side shouldn't have moved because all buys went
        // WETH → TOKEN (no TOKEN-side fee accrual yet).
        assertEq(IERC20(tokenAddress).balanceOf(creator), creatorTokenBefore);
    }
}
