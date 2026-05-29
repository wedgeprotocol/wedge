// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LaunchDeployer} from "../../src/LaunchDeployer.sol";
import {Launchpad} from "../../src/Launchpad.sol";

import {BaseMainnet} from "../../script/Constants.s.sol";
import {MainnetForkBase} from "./MainnetForkBase.sol";
import {TestSwapper} from "./helpers/TestSwapper.sol";

/// @notice Mainnet-fork: swap on the Wedge Rail and verify treasury
///         earns Rail fees (100% to treasury per the spec).
///
///         Sequence:
///           1. Bootstrap WEDGE via Classic Mainline + setProtocolToken.
///           2. Launch TOKEN with Balanced Wedge Rail extension.
///           3. Deal WEDGE to buyer (in production they'd acquire it
///              via Mainline; here we shortcut for test speed).
///           4. Swap WEDGE → TOKEN through the Rail pool.
///           5. WedgeRailLocker.collectFees → treasury receives WEDGE.
contract RailSwapMainnetFork is MainnetForkBase {
    using StateLibrary for IPoolManager;

    TestSwapper internal swapper;

    address internal creator;
    address internal buyer;

    int24 internal constant MAINLINE_STARTING_TICK = 230_200;
    int24 internal constant MAINLINE_TICK_SPACING = 200;

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

    function _classicConfig(bytes32 salt, string memory name, string memory symbol)
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

    function _bootstrapWedge() internal returns (address wedge) {
        wedge = launchpad.deployToken(_classicConfig(bytes32(uint256(0x57ED6E)), "Wedge", "WEDGE"));
        vm.prank(owner);
        launchpad.setProtocolToken(wedge);
    }

    function _launchTokenWithRail(bytes32 salt)
        internal
        returns (address tokenAddress, PoolKey memory railKey)
    {
        Launchpad.DeploymentConfig memory cfg = _classicConfig(salt, "Rail Test", "RAIL");
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(railExt),
            msgValue: 0,
            extensionBps: 2000,
            extensionData: abi.encode(MAINLINE_STARTING_TICK)
        });

        tokenAddress = launchpad.deployToken(cfg);

        address wedge = launchpad.PROTOCOL_TOKEN();
        (address c0, address c1) =
            tokenAddress < wedge ? (tokenAddress, wedge) : (wedge, tokenAddress);
        railKey = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    // ─────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────

    function test_rail_swap_wedge_for_token_succeeds() public {
        address wedge = _bootstrapWedge();
        (address tokenAddress, PoolKey memory railKey) = _launchTokenWithRail(bytes32(uint256(1)));

        // Deal WEDGE to buyer.
        uint256 wedgeIn = 1_000_000e18;
        deal(wedge, buyer, wedgeIn);
        vm.prank(buyer);
        IERC20(wedge).approve(address(swapper), wedgeIn);

        bool zeroForOne = Currency.unwrap(railKey.currency0) == wedge;
        uint256 tokenBefore = IERC20(tokenAddress).balanceOf(buyer);

        vm.prank(buyer);
        swapper.swap(railKey, wedgeIn, zeroForOne, buyer, buyer);

        uint256 tokenOut = IERC20(tokenAddress).balanceOf(buyer) - tokenBefore;
        assertTrue(tokenOut > 0, "rail swap yielded no token");
        assertEq(IERC20(wedge).balanceOf(buyer), 0, "buyer's wedge fully consumed");
    }

    function test_rail_sell_token_for_wedge_after_buy_seeds_pool() public {
        // The Rail starts with zero WEDGE (single-sided TOKEN seeding).
        // A TOKEN → WEDGE swap can only succeed after at least one
        // WEDGE → TOKEN buy has populated the pool's WEDGE side.
        address wedge = _bootstrapWedge();
        (address tokenAddress, PoolKey memory railKey) = _launchTokenWithRail(bytes32(uint256(3)));

        // Step 1: buyer pumps WEDGE into Rail, gets TOKEN out.
        uint256 wedgeIn = 1_000_000e18;
        deal(wedge, buyer, wedgeIn);
        vm.prank(buyer);
        IERC20(wedge).approve(address(swapper), wedgeIn);
        bool buyZeroForOne = Currency.unwrap(railKey.currency0) == wedge;
        vm.prank(buyer);
        swapper.swap(railKey, wedgeIn, buyZeroForOne, buyer, buyer);

        uint256 tokenAcquired = IERC20(tokenAddress).balanceOf(buyer);
        assertTrue(tokenAcquired > 0, "no token acquired in seed-buy");

        // Step 2: a different seller sends some of THEIR TOKEN into Rail
        // for WEDGE. (Deal a fresh TOKEN balance to a fresh seller so
        // we're not double-counting the buyer.)
        address seller = makeAddr("seller");
        deal(tokenAddress, seller, tokenAcquired / 2);
        vm.prank(seller);
        IERC20(tokenAddress).approve(address(swapper), tokenAcquired / 2);

        bool sellZeroForOne = Currency.unwrap(railKey.currency0) == tokenAddress;
        uint256 sellerWedgeBefore = IERC20(wedge).balanceOf(seller);
        vm.prank(seller);
        swapper.swap(railKey, tokenAcquired / 2, sellZeroForOne, seller, seller);

        uint256 sellerWedgeOut = IERC20(wedge).balanceOf(seller) - sellerWedgeBefore;
        assertTrue(sellerWedgeOut > 0, "seller got no WEDGE back");
    }

    function test_rail_collectFees_routes_to_treasury() public {
        address wedge = _bootstrapWedge();
        (address tokenAddress, PoolKey memory railKey) = _launchTokenWithRail(bytes32(uint256(2)));

        // Swap to accrue some Rail LP fees.
        uint256 wedgeIn = 1_000_000e18;
        deal(wedge, buyer, wedgeIn);
        vm.prank(buyer);
        IERC20(wedge).approve(address(swapper), wedgeIn);
        bool zeroForOne = Currency.unwrap(railKey.currency0) == wedge;
        vm.prank(buyer);
        swapper.swap(railKey, wedgeIn, zeroForOne, buyer, buyer);

        uint256 treasuryWedgeBefore = IERC20(wedge).balanceOf(treasury);
        uint256 treasuryTokenBefore = IERC20(tokenAddress).balanceOf(treasury);

        // collectFees is permissionless. Per Phase 0.4, the Rail
        // locker forwards 100% of collected fees to teamFeeRecipient.
        vm.prank(makeAddr("anyone"));
        railLocker.collectFees(tokenAddress);

        // Treasury should have received some WEDGE (the LP-side fee
        // from the WEDGE-in swap).
        assertTrue(
            IERC20(wedge).balanceOf(treasury) > treasuryWedgeBefore,
            "treasury received no WEDGE from Rail"
        );
        // No TOKEN-side fees yet (only swapped WEDGE in).
        assertEq(IERC20(tokenAddress).balanceOf(treasury), treasuryTokenBefore);
    }
}
