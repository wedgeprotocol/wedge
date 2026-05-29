// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {WedgeRailExtension} from "../src/WedgeRailExtension.sol";
import {WedgeRailLocker} from "../src/WedgeRailLocker.sol";
import {IWedgeExtension} from "../src/interfaces/IWedgeExtension.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLaunchpadProtocolToken} from "./mocks/MockLaunchpadProtocolToken.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";

contract WedgeRailExtensionTest is Test {
    WedgeRailExtension internal ext;
    WedgeRailLocker internal locker;
    MockPoolManager internal pm;
    MockPositionManager internal posManager;
    MockLaunchpadProtocolToken internal launchpad;

    MockERC20 internal token;
    MockERC20 internal wedge;
    MockERC20 internal weth;

    address internal mainlineHook;

    int24 internal constant MAINLINE_STARTING_TICK = 230_200;
    uint256 internal constant SUPPLY = 20_000_000_000e18; // 20% of 100B

    function setUp() public {
        launchpad = new MockLaunchpadProtocolToken();
        pm = new MockPoolManager();
        posManager = new MockPositionManager();
        mainlineHook = makeAddr("mainlineHook");

        weth = new MockERC20("WETH", "WETH");
        wedge = new MockERC20("WEDGE", "WEDGE");

        // Deploy the locker first, then the extension, then wire them.
        locker = new WedgeRailLocker(address(launchpad), address(posManager));

        ext = new WedgeRailExtension(
            address(launchpad),
            address(locker),
            address(weth),
            mainlineHook,
            address(pm),
            address(posManager)
        );

        locker.setExtension(address(ext));

        launchpad.setProtocolToken(address(wedge));
    }

    // ─────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────

    /// @dev Deploys a mock token at an address satisfying the given
    ///      relation vs WEDGE. Loops until the addresses sort right.
    function _tokenLessThanWedge() internal returns (MockERC20 t) {
        for (uint256 nonce = 0; nonce < 256; nonce++) {
            address probe = address(uint160(uint256(keccak256(abi.encode("t", nonce)))));
            if (probe < address(wedge)) {
                vm.setNonce(address(this), uint64(nonce));
                t = new MockERC20("T", "T");
                if (address(t) < address(wedge)) return t;
            }
        }
        revert("could not find low address");
    }

    function _wedgeWethPoolId() internal view returns (PoolId) {
        (address c0, address c1) = address(wedge) < address(weth)
            ? (address(wedge), address(weth))
            : (address(weth), address(wedge));
        PoolKey memory k = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(mainlineHook)
        });
        return k.toId();
    }

    function _seedWedgeWethSpot(int24 tick) internal {
        // sqrtPriceX96 just needs to be nonzero so the
        // pool-initialized check passes.
        pm.setSlot0(_wedgeWethPoolId(), uint160(1 << 96), tick);
    }

    function _callReceiveTokens(address tokenAddr, int24 mainlineTick) internal {
        // Launchpad's flow: approve extension for supply, then call.
        token.mint(address(launchpad), SUPPLY);
        vm.startPrank(address(launchpad));
        IERC20(tokenAddr).approve(address(ext), SUPPLY);
        ext.receiveTokens(tokenAddr, SUPPLY, abi.encode(mainlineTick));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // Construction & interface
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_sets_immutables() public view {
        assertEq(ext.LAUNCHPAD(), address(launchpad));
        assertEq(ext.RAIL_LOCKER(), address(locker));
        assertEq(ext.WETH(), address(weth));
        assertEq(ext.MAINLINE_HOOK(), mainlineHook);
        assertEq(address(ext.POOL_MANAGER()), address(pm));
        assertEq(address(ext.POSITION_MANAGER()), address(posManager));
    }

    function test_supportsInterface_wedge_extension() public view {
        assertTrue(ext.supportsInterface(type(IWedgeExtension).interfaceId));
        assertFalse(ext.supportsInterface(bytes4(0xdeadbeef)));
    }

    function test_requiresProtocolToken_true() public view {
        assertTrue(ext.requiresProtocolToken());
    }

    function test_constants_match_spec() public view {
        assertEq(ext.RAIL_FEE(), 3000);
        assertEq(ext.RAIL_TICK_SPACING(), 60);
        assertEq(ext.BAND_1_BPS() + ext.BAND_2_BPS() + ext.BAND_3_BPS(), 10_000);
    }

    // ─────────────────────────────────────────────────────────────────
    // receiveTokens — auth
    // ─────────────────────────────────────────────────────────────────

    function test_receiveTokens_only_launchpad() public {
        token = new MockERC20("Token", "TKN");
        vm.expectRevert(WedgeRailExtension.OnlyLaunchpad.selector);
        ext.receiveTokens(address(token), SUPPLY, abi.encode(MAINLINE_STARTING_TICK));
    }

    function test_receiveTokens_reverts_if_protocol_token_unset() public {
        // Strip the protocol token after setup.
        launchpad.setProtocolToken(address(0));
        token = new MockERC20("Token", "TKN");
        token.mint(address(launchpad), SUPPLY);

        vm.startPrank(address(launchpad));
        IERC20(address(token)).approve(address(ext), SUPPLY);
        vm.expectRevert(WedgeRailExtension.ProtocolTokenNotSet.selector);
        ext.receiveTokens(address(token), SUPPLY, abi.encode(MAINLINE_STARTING_TICK));
        vm.stopPrank();
    }

    function test_receiveTokens_reverts_if_wedge_weth_pool_uninitialized() public {
        token = new MockERC20("Token", "TKN");
        token.mint(address(launchpad), SUPPLY);

        // No seed of wedge/weth slot0 — sqrtPriceX96 reads back as 0.
        vm.startPrank(address(launchpad));
        IERC20(address(token)).approve(address(ext), SUPPLY);
        vm.expectRevert(WedgeRailExtension.WedgeWethPoolNotInitialized.selector);
        ext.receiveTokens(address(token), SUPPLY, abi.encode(MAINLINE_STARTING_TICK));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // receiveTokens — happy path & state
    // ─────────────────────────────────────────────────────────────────

    function test_receiveTokens_opens_pool_mints_three_positions_transfers_nfts() public {
        token = new MockERC20("Token", "TKN");
        _seedWedgeWethSpot(0); // wedge ≈ weth price → rail tick ≈ mainline tick
        posManager.setNextTokenId(100);

        _callReceiveTokens(address(token), MAINLINE_STARTING_TICK);

        // Pool was initialized once
        assertEq(pm.initializeCallCount(), 1);

        // modifyLiquidities was called once with 3 mints + settle
        assertEq(posManager.callCount(), 1);
        (bytes memory actions, bytes[] memory params) = posManager.decodeLastActions();
        assertEq(actions.length, 4);
        assertEq(uint8(actions[0]), uint8(Actions.MINT_POSITION));
        assertEq(uint8(actions[1]), uint8(Actions.MINT_POSITION));
        assertEq(uint8(actions[2]), uint8(Actions.MINT_POSITION));
        assertEq(uint8(actions[3]), uint8(Actions.SETTLE_PAIR));
        assertEq(params.length, 4);

        // Three NFT transfers to the locker, sequential IDs from 100.
        assertEq(posManager.safeTransferFromCallCount(), 3);
        assertEq(posManager.lastTransferTo(), address(locker));
        assertEq(posManager.lastTransferTokenId(), 102); // last of {100,101,102}
        assertEq(posManager.lastTransferFrom(), address(ext));
    }

    function test_receiveTokens_emits_RailOpened() public {
        token = new MockERC20("Token", "TKN");
        _seedWedgeWethSpot(0);
        posManager.setNextTokenId(50);

        token.mint(address(launchpad), SUPPLY);
        vm.startPrank(address(launchpad));
        IERC20(address(token)).approve(address(ext), SUPPLY);

        vm.expectEmit(true, true, false, false, address(ext));
        emit WedgeRailExtension.RailOpened(address(token), address(wedge), bytes32(0), 0, 50);
        ext.receiveTokens(address(token), SUPPLY, abi.encode(MAINLINE_STARTING_TICK));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // Tick math
    // ─────────────────────────────────────────────────────────────────

    function test_rail_tick_equals_mainline_when_wedge_eq_weth_in_value() public {
        token = new MockERC20("Token", "TKN");
        // Effective wedge/weth tick = 0 → rail tick = mainline tick
        _seedWedgeWethSpot(0);

        _callReceiveTokens(address(token), MAINLINE_STARTING_TICK);

        // The pool was initialised at sqrtPrice corresponding to the
        // expected tick. Decoding is fiddly; assert via direct
        // recomputation: when wedge effective tick is 0, rail tick
        // (TOKEN-as-currency0 frame) = mainlineTick = 230_200. Aligned
        // to spacing 60 toward zero: 230_160 (since 230_200 % 60 = 40).
        int24 expectedRailTick = 230_200 - (230_200 % 60);
        // Pool tick orientation: token < wedge or token > wedge?
        if (address(token) > address(wedge)) {
            expectedRailTick = -expectedRailTick;
        }

        uint160 expectedSqrt = TickMath.getSqrtPriceAtTick(expectedRailTick);
        assertEq(pm.lastSqrtPriceX96(), expectedSqrt);
    }

    function test_rail_tick_subtracts_wedge_weth_offset() public {
        token = new MockERC20("Token", "TKN");
        // Effective wedge/weth tick = 23_000 (≈ 1 WEDGE = ~0.1 WETH).
        // Rail tick (TOKEN-as-currency0) = mainlineTick - 23_000 = 207_200.
        int24 effectiveWedgeWethTick = 23_000;
        // Translate to actual wedge/weth pool tick (depends on orientation).
        int24 wedgeWethPoolTick =
            address(wedge) < address(weth) ? effectiveWedgeWethTick : -effectiveWedgeWethTick;
        _seedWedgeWethSpot(wedgeWethPoolTick);

        _callReceiveTokens(address(token), MAINLINE_STARTING_TICK);

        int24 expectedEffective = MAINLINE_STARTING_TICK - effectiveWedgeWethTick;
        int24 expectedRailTick = expectedEffective - (expectedEffective % 60);
        if (address(token) > address(wedge)) {
            expectedRailTick = -expectedRailTick;
        }

        uint160 expectedSqrt = TickMath.getSqrtPriceAtTick(expectedRailTick);
        assertEq(pm.lastSqrtPriceX96(), expectedSqrt);
    }

    // ─────────────────────────────────────────────────────────────────
    // Pool key shape
    // ─────────────────────────────────────────────────────────────────

    function test_rail_pool_is_hookless_and_uses_rail_fee_tier() public {
        token = new MockERC20("Token", "TKN");
        _seedWedgeWethSpot(0);

        _callReceiveTokens(address(token), MAINLINE_STARTING_TICK);

        // MockPoolManager records lastInitKey.
        (Currency c0, Currency c1, uint24 fee, int24 spacing, IHooks hooks) = pm.lastInitKey();
        c0; // silence unused
        c1;
        assertEq(fee, 3000);
        assertEq(spacing, 60);
        assertEq(address(hooks), address(0));
    }

    function test_rail_pool_currency_ordering() public {
        token = new MockERC20("Token", "TKN");
        _seedWedgeWethSpot(0);

        _callReceiveTokens(address(token), MAINLINE_STARTING_TICK);

        (Currency c0, Currency c1,,,) = pm.lastInitKey();
        address tokenAddr = address(token);
        address wedgeAddr = address(wedge);
        (address expectC0, address expectC1) =
            tokenAddr < wedgeAddr ? (tokenAddr, wedgeAddr) : (wedgeAddr, tokenAddr);
        assertEq(Currency.unwrap(c0), expectC0);
        assertEq(Currency.unwrap(c1), expectC1);
    }
}
