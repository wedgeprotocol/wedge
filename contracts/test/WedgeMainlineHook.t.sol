// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Test} from "forge-std/Test.sol";

import {WedgeMainlineHook} from "../src/WedgeMainlineHook.sol";
import {WedgeMevDescendingFees} from "../src/WedgeMevDescendingFees.sol";
import {IWedgeHook} from "../src/interfaces/IWedgeHook.sol";
import {IWedgeMevModule} from "../src/interfaces/IWedgeMevModule.sol";

import {MockPoolManager} from "./mocks/MockPoolManager.sol";

contract WedgeMainlineHookTest is Test {
    WedgeMainlineHook internal hook;
    MockPoolManager internal pm;
    WedgeMevDescendingFees internal mev;

    address internal factory;
    address internal locker;
    address internal tokenLow; // address(0xA000...) — sorts as currency0
    address internal tokenHigh; // address(0xB000...) — sorts as currency1
    address internal stranger;

    int24 internal constant TICK_IF_TOKEN0 = 230_200;
    int24 internal constant TICK_SPACING = 200;

    function setUp() public {
        factory = makeAddr("factory");
        locker = makeAddr("locker");
        stranger = makeAddr("stranger");
        tokenLow = makeAddr("tokenLow");
        tokenHigh = makeAddr("tokenHigh");
        // Ensure deterministic ordering: tokenLow < tokenHigh.
        if (tokenLow > tokenHigh) {
            (tokenLow, tokenHigh) = (tokenHigh, tokenLow);
        }

        pm = new MockPoolManager();
        hook = new WedgeMainlineHook(factory, address(pm));
        mev = new WedgeMevDescendingFees();
    }

    // ─────────────────────────────────────────────────────────────────
    // Construction & introspection
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_sets_immutables() public view {
        assertEq(hook.FACTORY(), factory);
        assertEq(address(hook.POOL_MANAGER()), address(pm));
        assertEq(hook.BASE_LP_FEE(), 10_000);
        assertEq(hook.HOOK_FEE_NUMERATOR(), 200_000);
    }

    function test_supportsInterface_wedge_hook() public view {
        assertTrue(hook.supportsInterface(type(IWedgeHook).interfaceId));
        assertFalse(hook.supportsInterface(bytes4(0xdeadbeef)));
    }

    // ─────────────────────────────────────────────────────────────────
    // initializePool — auth
    // ─────────────────────────────────────────────────────────────────

    function test_initializePool_only_factory() public {
        vm.prank(stranger);
        vm.expectRevert(IWedgeHook.OnlyFactory.selector);
        hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
    }

    function test_initializePool_rejects_zero_token_launched() public {
        vm.prank(factory);
        vm.expectRevert(IWedgeHook.ETHPoolNotAllowed.selector);
        hook.initializePool(
            address(0), tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
    }

    function test_initializePool_rejects_zero_paired() public {
        vm.prank(factory);
        vm.expectRevert(IWedgeHook.ETHPoolNotAllowed.selector);
        hook.initializePool(
            tokenLow, address(0), TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
    }

    // ─────────────────────────────────────────────────────────────────
    // initializePool — orientation & state
    // ─────────────────────────────────────────────────────────────────

    function test_initializePool_token_low_address_is_currency0() public {
        // tokenLow (0xA00…) < tokenHigh (0xB00…), so tokenLow is the
        // launched token at currency0.
        vm.prank(factory);
        PoolKey memory key = hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );

        assertEq(Currency.unwrap(key.currency0), tokenLow);
        assertEq(Currency.unwrap(key.currency1), tokenHigh);
        assertEq(key.fee, LPFeeLibrary.DYNAMIC_FEE_FLAG);
        assertEq(key.tickSpacing, TICK_SPACING);
        assertEq(address(key.hooks), address(hook));

        (address lk, address mv, bool t0, bool init) = hook.pools(key.toId());
        assertEq(lk, locker);
        assertEq(mv, address(mev));
        assertTrue(t0);
        assertTrue(init);

        assertTrue(pm.initializeCalled());
    }

    function test_initializePool_token_high_address_is_currency1() public {
        // Launched token has the high address: paired = currency0, launched = currency1.
        vm.prank(factory);
        PoolKey memory key = hook.initializePool(
            tokenHigh, tokenLow, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );

        assertEq(Currency.unwrap(key.currency0), tokenLow);
        assertEq(Currency.unwrap(key.currency1), tokenHigh);

        (,, bool t0,) = hook.pools(key.toId());
        assertFalse(t0);
    }

    function test_initializePool_reverts_on_duplicate() public {
        vm.startPrank(factory);
        hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
        vm.expectRevert(WedgeMainlineHook.PoolAlreadyInitialized.selector);
        hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
        vm.stopPrank();
    }

    function test_initializePool_emits_event() public {
        vm.prank(factory);
        // Don't check the poolId topic (it's deterministic but tedious to recompute here);
        // assert on the address topics and data instead.
        vm.expectEmit(false, true, true, true, address(hook));
        emit WedgeMainlineHook.PoolInitialized(
            PoolId.wrap(bytes32(0)), tokenLow, tokenHigh, TICK_IF_TOKEN0, locker, address(mev)
        );
        hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );
    }

    // ─────────────────────────────────────────────────────────────────
    // initializeMevModule
    // ─────────────────────────────────────────────────────────────────

    function test_initializeMevModule_only_factory() public {
        vm.prank(factory);
        PoolKey memory key = hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );

        vm.prank(stranger);
        vm.expectRevert(IWedgeHook.OnlyFactory.selector);
        hook.initializeMevModule(key, "");
    }

    function test_initializeMevModule_reverts_if_pool_not_initialized() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(tokenLow),
            currency1: Currency.wrap(tokenHigh),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        vm.prank(factory);
        vm.expectRevert(WedgeMainlineHook.PoolNotInitialized.selector);
        hook.initializeMevModule(key, "");
    }

    function test_initializeMevModule_forwards_to_module() public {
        vm.prank(factory);
        PoolKey memory key = hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );

        bytes memory cfg = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: 800_000, endingFee: 12_000, secondsToDecay: 120
            })
        );
        vm.prank(factory);
        hook.initializeMevModule(key, cfg);

        // Confirm the MEV module recorded the pool start time.
        assertEq(mev.poolStartTime(key.toId()), block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────
    // beforeSwap / afterSwap — auth
    // ─────────────────────────────────────────────────────────────────

    function test_beforeSwap_only_poolManager() public {
        vm.prank(factory);
        PoolKey memory key = hook.initializePool(
            tokenLow, tokenHigh, TICK_IF_TOKEN0, TICK_SPACING, locker, address(mev), ""
        );

        IPoolManagerSwapParamsLike memory params;
        vm.prank(stranger);
        vm.expectRevert(WedgeMainlineHook.OnlyPoolManager.selector);
        // call via low-level so we don't need to import IPoolManager.SwapParams shape here
        (bool ok,) = address(hook)
            .call(
                abi.encodeWithSignature(
                    "beforeSwap(address,(address,address,uint24,int24,address),(bool,int256,uint160),bytes)",
                    address(0),
                    key,
                    params,
                    bytes("")
                )
            );
        ok; // silence unused
    }

    /// @dev Placeholder type to keep the cast above compiling; the
    ///      low-level call deliberately doesn't pack a real SwapParams
    ///      since beforeSwap is expected to revert before decoding.
    struct IPoolManagerSwapParamsLike {
        uint256 _padding;
    }
}
