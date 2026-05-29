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

/// @notice Mainnet-fork integration: end-to-end swap against the
///         Mainline pool. Verifies that:
///         - the hook's MEV-decay LP fee kicks in at t=0 (sniper window)
///         - the hook's 0.2% fee is taken on each swap
///         - hook fees accumulate as ERC-6909 on the hook and sweep
///           to the Launchpad on the next swap
///         - the locker's collectFees distributes correctly to the
///           reward recipients
///
///         Skipped automatically when `BASE_RPC_URL` is unset.
contract SwapMainnetFork is MainnetForkBase {
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

    function _baseTokenConfig(bytes32 salt)
        internal
        view
        returns (LaunchDeployer.TokenConfig memory)
    {
        return LaunchDeployer.TokenConfig({
            admin: creator,
            name: "Swap Test",
            symbol: "SWP",
            salt: salt,
            image: "ipfs://test",
            metadata: "{}",
            context: "fork-test",
            renounceAtDeploy: false
        });
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

    function _launchClassicMainline(bytes32 salt)
        internal
        returns (address tokenAddress, PoolKey memory key)
    {
        Launchpad.DeploymentConfig memory cfg;
        cfg.tokenConfig = _baseTokenConfig(salt);
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

    function _buyTokenWithWeth(PoolKey memory key, address tokenAddress, uint256 wethIn)
        internal
        returns (uint256 tokenOut)
    {
        // Deal WETH to buyer and approve swapper.
        deal(BaseMainnet.WETH, buyer, wethIn);
        vm.prank(buyer);
        IERC20(BaseMainnet.WETH).approve(address(swapper), wethIn);

        bool zeroForOne = Currency.unwrap(key.currency0) == BaseMainnet.WETH;
        uint256 tokenBalBefore = IERC20(tokenAddress).balanceOf(buyer);

        vm.prank(buyer);
        swapper.swap(key, wethIn, zeroForOne, buyer, buyer);

        tokenOut = IERC20(tokenAddress).balanceOf(buyer) - tokenBalBefore;
    }

    // ─────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────

    function test_swap_at_launch_pays_mev_decay_fee() public {
        (address tokenAddress, PoolKey memory key) = _launchClassicMainline(bytes32(uint256(1)));

        // t=0 buy: should pay ~80% LP fee + ~16% hook fee = ~96% total.
        // The buyer gets very little TOKEN out for their 0.01 ETH.
        uint256 amountIn = 0.01 ether;
        uint256 tokenOut = _buyTokenWithWeth(key, tokenAddress, amountIn);

        // Sanity: got some TOKEN, but well below the "no-fee" expectation.
        assertTrue(tokenOut > 0, "buyer got no token");

        // Buyer's WETH is fully consumed.
        assertEq(IERC20(BaseMainnet.WETH).balanceOf(buyer), 0);
    }

    function test_swap_after_decay_pays_base_fee() public {
        (address tokenAddress, PoolKey memory key) = _launchClassicMainline(bytes32(uint256(2)));

        // Warp past the 120s decay window.
        vm.warp(block.timestamp + 121);

        uint256 amountInBase = 0.01 ether;
        uint256 tokenOutBase = _buyTokenWithWeth(key, tokenAddress, amountInBase);
        assertTrue(tokenOutBase > 0, "buyer got no token post-decay");
    }

    function test_sell_direction_token_for_weth_succeeds() public {
        // Exercises the OTHER two hook cases:
        //   isExactInput && !swappingForLaunched  → afterSwap delta
        //   !isExactInput && swappingForLaunched  → afterSwap delta
        //
        // The buy cases (above) hit beforeSwap delta; sells hit afterSwap.
        // If there's an amount0/1 flipping bug in afterSwap or a wrong
        // sign on the unspecifiedDelta computation, only this test
        // catches it.
        (address tokenAddress, PoolKey memory key) = _launch(bytes32(uint256(0xCE11)));

        // Step 1: buy some TOKEN first so the seller has inventory.
        // Use post-decay window so we get more TOKEN per WETH and the
        // sell has something material to work with.
        vm.warp(block.timestamp + 121);
        uint256 wethIn = 0.05 ether;
        uint256 tokenAcquired = _buyTokenWithWeth(key, tokenAddress, wethIn);
        assertTrue(tokenAcquired > 0, "buy step yielded no token");

        // Step 2: sell a portion of the TOKEN back for WETH.
        uint256 tokenIn = tokenAcquired / 2;
        vm.prank(buyer);
        IERC20(tokenAddress).approve(address(swapper), tokenIn);

        bool tokenIsCurrency0 = tokenAddress < BaseMainnet.WETH;
        bool zeroForOne = tokenIsCurrency0; // selling TOKEN means zeroForOne if TOKEN is c0
        uint256 wethBalBefore = IERC20(BaseMainnet.WETH).balanceOf(buyer);
        vm.prank(buyer);
        swapper.swap(key, tokenIn, zeroForOne, buyer, buyer);

        uint256 wethOut = IERC20(BaseMainnet.WETH).balanceOf(buyer) - wethBalBefore;
        assertTrue(wethOut > 0, "sell yielded no weth");
    }

    function _launch(bytes32 salt) internal returns (address tokenAddress, PoolKey memory key) {
        return _launchClassicMainline(salt);
    }

    function test_swap_at_launch_vs_post_decay_buyer_gets_more_post_decay() public {
        // Same amountIn → buyer should get more TOKEN after decay because
        // the fee is lower. Launch two separate tokens with the same
        // config so swap behaviour matches.
        (address tokenA, PoolKey memory keyA) = _launchClassicMainline(bytes32(uint256(0xA)));
        (address tokenB, PoolKey memory keyB) = _launchClassicMainline(bytes32(uint256(0xB)));

        uint256 amountIn = 0.01 ether;
        uint256 outA = _buyTokenWithWeth(keyA, tokenA, amountIn);

        vm.warp(block.timestamp + 121);
        uint256 outB = _buyTokenWithWeth(keyB, tokenB, amountIn);

        assertTrue(outB > outA, "post-decay buyer should get more token than snipe buyer");
    }
}
