// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {Test} from "forge-std/Test.sol";

import {LaunchToken} from "../src/LaunchToken.sol";
import {WedgeLpLocker} from "../src/WedgeLpLocker.sol";
import {IWedgeLpLocker} from "../src/interfaces/IWedgeLpLocker.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";

contract WedgeLpLockerTest is Test {
    WedgeLpLocker internal locker;
    MockPositionManager internal pm;
    LaunchToken internal token;
    MockERC20 internal weth;

    address internal launchpad;
    address internal creator;
    address internal stranger;
    address internal otherRecipient;

    int24 internal constant STARTING_TICK = 230_200;
    int24 internal constant TICK_SPACING = 200;
    uint256 internal constant SUPPLY = 80_000_000_000e18; // 80B (post-Rail split)

    function setUp() public {
        launchpad = makeAddr("launchpad");
        creator = makeAddr("creator");
        stranger = makeAddr("stranger");
        otherRecipient = makeAddr("otherRecipient");

        weth = new MockERC20("Wrapped Ether", "WETH");

        pm = new MockPositionManager();
        locker = new WedgeLpLocker(launchpad, address(pm));

        vm.prank(launchpad);
        token = new LaunchToken({
            name_: "Test",
            symbol_: "TEST",
            maxSupply_: 100_000_000_000e18,
            admin_: creator,
            image_: "ipfs://x",
            metadata_: "{}",
            context_: "ctx",
            renounceAtDeploy_: false
        });
    }

    // ─────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────

    function _poolKey() internal returns (PoolKey memory) {
        address tokenAddr = address(token);
        address wethAddr = address(weth);
        bool token0IsLaunched = tokenAddr < wethAddr;
        return PoolKey({
            currency0: Currency.wrap(token0IsLaunched ? tokenAddr : wethAddr),
            currency1: Currency.wrap(token0IsLaunched ? wethAddr : tokenAddr),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(makeAddr("hook"))
        });
    }

    function _defaultConfig()
        internal
        view
        returns (IWedgeLpLocker.PlaceLiquidityConfig memory cfg)
    {
        // 5-band Mainline: 10/50/15/20/5 (of the 80% Mainline share)
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

    function _place() internal {
        // Launchpad already received the full supply at construction.
        // Approve the locker and call placeLiquidity from the launchpad.
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        locker.placeLiquidity(
            _defaultConfig(), _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token)
        );
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // Construction & interface
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_sets_immutables() public view {
        assertEq(locker.LAUNCHPAD(), launchpad);
        assertEq(address(locker.POSITION_MANAGER()), address(pm));
    }

    function test_supportsInterface_wedge_lp_locker() public view {
        assertTrue(locker.supportsInterface(type(IWedgeLpLocker).interfaceId));
        assertFalse(locker.supportsInterface(bytes4(0xdeadbeef)));
    }

    // ─────────────────────────────────────────────────────────────────
    // placeLiquidity — auth & validation
    // ─────────────────────────────────────────────────────────────────

    function test_placeLiquidity_only_launchpad() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        vm.prank(stranger);
        vm.expectRevert(WedgeLpLocker.OnlyLaunchpad.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
    }

    function test_placeLiquidity_reverts_on_duplicate() public {
        _place();

        // Mint more supply (impossible for a real launch, but useful for the test).
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.AlreadyPlaced.selector);
        locker.placeLiquidity(
            _defaultConfig(), _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token)
        );
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_position_bps_sum_mismatch() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        cfg.positionBps[4] = 600; // sum now 10_100
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.PositionBpsSumMismatch.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_reward_bps_sum_mismatch() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        cfg.rewardBps[0] = 9999;
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.RewardBpsSumMismatch.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_tick_below_starting() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        cfg.tickLower[0] = STARTING_TICK - 200;
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.TickLowerBelowStartingTick.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_tick_not_multiple_of_spacing() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        cfg.tickLower[0] = STARTING_TICK + 50; // 200-spacing requires multiples of 200
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.TickNotMultipleOfSpacing.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_ticks_backwards() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg = _defaultConfig();
        cfg.tickUpper[0] = cfg.tickLower[0] - 200;
        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.TicksBackwards.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    function test_placeLiquidity_rejects_empty_arrays() public {
        IWedgeLpLocker.PlaceLiquidityConfig memory cfg;
        cfg.tickLower = new int24[](0);
        cfg.tickUpper = new int24[](0);
        cfg.positionBps = new uint16[](0);
        cfg.rewardAdmins = new address[](1);
        cfg.rewardAdmins[0] = creator;
        cfg.rewardRecipients = new address[](1);
        cfg.rewardRecipients[0] = creator;
        cfg.rewardBps = new uint16[](1);
        cfg.rewardBps[0] = 10_000;

        // launchpad already holds the full supply from setUp
        vm.startPrank(launchpad);
        IERC20(address(token)).approve(address(locker), SUPPLY);
        vm.expectRevert(WedgeLpLocker.EmptyArray.selector);
        locker.placeLiquidity(cfg, _poolKey(), STARTING_TICK, TICK_SPACING, SUPPLY, address(token));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // placeLiquidity — happy path
    // ─────────────────────────────────────────────────────────────────

    function test_placeLiquidity_records_state() public {
        pm.setNextTokenId(42);
        _place();

        assertTrue(locker.isPlaced(address(token)));
        WedgeLpLocker.Position[] memory positions = locker.positionsOf(address(token));
        assertEq(positions.length, 5);
        assertEq(positions[0].tokenId, 42);
        assertEq(positions[1].tokenId, 43);
        assertEq(positions[4].tokenId, 46);
        assertEq(positions[0].positionBps, 1000);
        assertEq(positions[1].positionBps, 5000);
    }

    function test_placeLiquidity_builds_action_sequence() public {
        _place();
        (bytes memory actions, bytes[] memory params) = pm.decodeLastActions();
        // 5 mints + 1 settle
        assertEq(actions.length, 6);
        assertEq(uint8(actions[0]), uint8(Actions.MINT_POSITION));
        assertEq(uint8(actions[4]), uint8(Actions.MINT_POSITION));
        assertEq(uint8(actions[5]), uint8(Actions.SETTLE_PAIR));
        assertEq(params.length, 6);
    }

    function test_placeLiquidity_encodes_ticks_flipped_for_token_is_currency1() public {
        // Default setUp deploys token at an address > weth — confirm
        // the orientation we're exercising before asserting.
        assertTrue(address(token) > address(weth));

        _place();
        (, bytes[] memory params) = pm.decodeLastActions();

        // First MINT_POSITION params: (poolKey, tickLower, tickUpper, ...)
        (, int24 encodedLower, int24 encodedUpper,,,,,) = abi.decode(
            params[0], (PoolKey, int24, int24, uint128, uint128, uint128, address, bytes)
        );
        // Band 1 of default config (as-currency-0 frame): lower=230_200,
        // upper=237_200. With TOKEN as currency1 on the actual pool,
        // ticks are negated and the pair swapped:
        //   actualLower = -237_200, actualUpper = -230_200.
        assertEq(encodedLower, int24(-237_200));
        assertEq(encodedUpper, int24(-230_200));
    }

    function test_placeLiquidity_encodes_ticks_unflipped_for_token_is_currency0() public {
        // Force the TOKEN < WETH orientation by re-deploying the token
        // at a controlled address. We do this by deploying a fresh
        // MockERC20 from a high-nonce account whose CREATE address
        // happens to be > weth; then re-deploying it from a low-nonce
        // account until the result is < weth.
        address tokenDeployer = makeAddr("tokenDeployer");
        MockERC20 lowToken;
        for (uint64 nonce = 0; nonce < 20; nonce++) {
            vm.setNonce(tokenDeployer, nonce);
            vm.prank(tokenDeployer);
            MockERC20 candidate = new MockERC20("Low", "LOW");
            if (address(candidate) < address(weth)) {
                lowToken = candidate;
                break;
            }
        }
        require(address(lowToken) != address(0), "could not find low-address token");
        require(address(lowToken) < address(weth), "ordering invariant");

        lowToken.mint(launchpad, SUPPLY);

        // Build the pool key with lowToken as currency0.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(lowToken)),
            currency1: Currency.wrap(address(weth)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(makeAddr("hook"))
        });

        vm.startPrank(launchpad);
        IERC20(address(lowToken)).approve(address(locker), SUPPLY);
        locker.placeLiquidity(
            _defaultConfig(), key, STARTING_TICK, TICK_SPACING, SUPPLY, address(lowToken)
        );
        vm.stopPrank();

        (, bytes[] memory params) = pm.decodeLastActions();
        (, int24 encodedLower, int24 encodedUpper,,,,,) = abi.decode(
            params[0], (PoolKey, int24, int24, uint128, uint128, uint128, address, bytes)
        );
        // When TOKEN < WETH, ticks pass through unflipped.
        assertEq(encodedLower, int24(230_200));
        assertEq(encodedUpper, int24(237_200));
    }

    function test_placeLiquidity_records_rewards() public {
        _place();
        (address[] memory admins, address[] memory recipients, uint16[] memory bps) =
            locker.rewardsOf(address(token));
        assertEq(admins.length, 1);
        assertEq(admins[0], creator);
        assertEq(recipients[0], creator);
        assertEq(bps[0], 10_000);
    }

    function test_placeLiquidity_pulls_supply() public {
        uint256 before_ = token.balanceOf(launchpad);
        _place();
        assertEq(token.balanceOf(launchpad), before_ - SUPPLY);
    }

    // ─────────────────────────────────────────────────────────────────
    // collectFees — distribution
    // ─────────────────────────────────────────────────────────────────

    function test_collectFees_reverts_token_not_placed() public {
        vm.expectRevert(WedgeLpLocker.TokenNotPlaced.selector);
        locker.collectFees(address(token));
    }

    function test_collectFees_builds_action_sequence() public {
        _place();
        locker.collectFees(address(token));
        (bytes memory actions,) = pm.decodeLastActions();
        // 5 decrease + 1 take pair
        assertEq(actions.length, 6);
        assertEq(uint8(actions[0]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[4]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[5]), uint8(Actions.TAKE_PAIR));
    }

    function test_collectFees_distributes_to_single_recipient() public {
        _place();
        // Simulate the PositionManager's TAKE_PAIR landing token0/token1
        // on the locker. WETH side: deal directly. TOKEN side: transfer
        // some leftover token.
        deal(address(token), address(locker), 1000e18);

        vm.prank(stranger);
        locker.collectFees(address(token));

        // 100% to creator
        assertEq(token.balanceOf(creator), 1000e18);
        assertEq(token.balanceOf(address(locker)), 0);
    }

    function test_collectFees_distributes_to_multiple_recipients() public {
        _place();
        // Update rewards to split 60/40 between creator and otherRecipient.
        address[] memory admins = new address[](1);
        admins[0] = creator;
        address[] memory recipients = new address[](2);
        recipients[0] = creator;
        recipients[1] = otherRecipient;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 6000;
        bps[1] = 4000;

        vm.prank(creator);
        locker.updateRewards(address(token), admins, recipients, bps);

        deal(address(token), address(locker), 1000e18);
        locker.collectFees(address(token));

        assertEq(token.balanceOf(creator), 600e18);
        assertEq(token.balanceOf(otherRecipient), 400e18);
    }

    function test_collectFees_handles_dust_via_last_recipient() public {
        _place();
        // Three-way split that doesn't divide cleanly: 3333/3333/3334.
        address[] memory admins = new address[](1);
        admins[0] = creator;
        address[] memory recipients = new address[](3);
        recipients[0] = creator;
        recipients[1] = otherRecipient;
        recipients[2] = makeAddr("third");
        uint16[] memory bps = new uint16[](3);
        bps[0] = 3333;
        bps[1] = 3333;
        bps[2] = 3334;

        vm.prank(creator);
        locker.updateRewards(address(token), admins, recipients, bps);

        deal(address(token), address(locker), 100); // 100 wei — forces rounding
        locker.collectFees(address(token));

        assertEq(token.balanceOf(creator), 33);
        assertEq(token.balanceOf(otherRecipient), 33);
        // Last recipient takes remainder = 100 - 33 - 33 = 34
        assertEq(token.balanceOf(recipients[2]), 34);
    }

    // ─────────────────────────────────────────────────────────────────
    // updateRewards
    // ─────────────────────────────────────────────────────────────────

    function test_updateRewards_only_admin() public {
        _place();
        address[] memory admins = new address[](1);
        admins[0] = stranger;
        address[] memory recipients = new address[](1);
        recipients[0] = stranger;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 10_000;

        vm.prank(stranger);
        vm.expectRevert(WedgeLpLocker.NotRewardAdmin.selector);
        locker.updateRewards(address(token), admins, recipients, bps);
    }

    function test_updateRewards_admin_can_replace_admin_set() public {
        _place();
        address newAdmin = makeAddr("newAdmin");

        address[] memory admins = new address[](1);
        admins[0] = newAdmin;
        address[] memory recipients = new address[](1);
        recipients[0] = newAdmin;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 10_000;

        vm.prank(creator);
        locker.updateRewards(address(token), admins, recipients, bps);

        (address[] memory adminList,,) = locker.rewardsOf(address(token));
        assertEq(adminList[0], newAdmin);

        // Old creator is no longer admin
        vm.prank(creator);
        vm.expectRevert(WedgeLpLocker.NotRewardAdmin.selector);
        locker.updateRewards(address(token), admins, recipients, bps);
    }

    function test_updateRewards_rejects_bps_sum_mismatch() public {
        _place();
        address[] memory admins = new address[](1);
        admins[0] = creator;
        address[] memory recipients = new address[](2);
        recipients[0] = creator;
        recipients[1] = otherRecipient;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 5000;
        bps[1] = 4000; // sum 9_000

        vm.prank(creator);
        vm.expectRevert(WedgeLpLocker.RewardBpsSumMismatch.selector);
        locker.updateRewards(address(token), admins, recipients, bps);
    }
}
