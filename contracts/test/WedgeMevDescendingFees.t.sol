// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Test} from "forge-std/Test.sol";

import {WedgeMevDescendingFees} from "../src/WedgeMevDescendingFees.sol";
import {IWedgeMevModule} from "../src/interfaces/IWedgeMevModule.sol";

import {MockWedgeHook} from "./mocks/MockWedgeHook.sol";

contract WedgeMevDescendingFeesTest is Test {
    WedgeMevDescendingFees internal module;
    MockWedgeHook internal hook;
    PoolKey internal poolKey;
    PoolId internal poolId;

    // Industry default: 80% start, 1.2% terminal, 120s duration
    uint24 internal constant DEFAULT_START_FEE = 800_000;
    uint24 internal constant DEFAULT_END_FEE = 12_000;
    uint32 internal constant DEFAULT_SECONDS = 120;

    function setUp() public {
        module = new WedgeMevDescendingFees();
        hook = new MockWedgeHook();
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 10_000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
    }

    function _initDefault() internal {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE,
                endingFee: DEFAULT_END_FEE,
                secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(address(hook));
        module.initialize(poolKey, data);
    }

    // ─────────────────────────────────────────────────────────────────
    // initialize — auth & validation
    // ─────────────────────────────────────────────────────────────────

    function test_initialize_only_hook() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE,
                endingFee: DEFAULT_END_FEE,
                secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.expectRevert(WedgeMevDescendingFees.OnlyHook.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_non_wedge_hook() public {
        // Hook with no supportsInterface support
        address fakeHook = makeAddr("fake");
        vm.etch(fakeHook, hex"00");
        PoolKey memory fakeKey = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 10_000,
            tickSpacing: 200,
            hooks: IHooks(fakeHook)
        });
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE,
                endingFee: DEFAULT_END_FEE,
                secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(fakeHook);
        vm.expectRevert();
        module.initialize(fakeKey, data);
    }

    function test_initialize_one_shot() public {
        _initDefault();
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE,
                endingFee: DEFAULT_END_FEE,
                secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.PoolAlreadyInitialized.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_zero_starting_fee() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: 0, endingFee: 0, secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.StartingFeeMustBeGreaterThanZero.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_starting_le_ending() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: 10_000, endingFee: 10_000, secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.StartingFeeMustBeGreaterThanEndingFee.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_starting_above_max() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: 1_000_001, endingFee: 12_000, secondsToDecay: DEFAULT_SECONDS
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.StartingFeeAboveMaximum.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_zero_decay() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE, endingFee: DEFAULT_END_FEE, secondsToDecay: 0
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.SecondsToDecayMustBeGreaterThanZero.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_rejects_decay_above_max() public {
        bytes memory data = abi.encode(
            WedgeMevDescendingFees.FeeConfig({
                startingFee: DEFAULT_START_FEE, endingFee: DEFAULT_END_FEE, secondsToDecay: 601
            })
        );
        vm.prank(address(hook));
        vm.expectRevert(WedgeMevDescendingFees.SecondsToDecayAboveMaximum.selector);
        module.initialize(poolKey, data);
    }

    function test_initialize_emits_and_records() public {
        vm.expectEmit(true, false, false, true, address(module));
        emit WedgeMevDescendingFees.FeeConfigSet(
            poolId, DEFAULT_START_FEE, DEFAULT_END_FEE, DEFAULT_SECONDS
        );
        _initDefault();

        (uint24 sf, uint24 ef, uint32 d) = module.feeConfig(poolId);
        assertEq(sf, DEFAULT_START_FEE);
        assertEq(ef, DEFAULT_END_FEE);
        assertEq(d, DEFAULT_SECONDS);
        assertEq(module.poolStartTime(poolId), block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────
    // getFee — decay shape
    // ─────────────────────────────────────────────────────────────────

    function test_getFee_uninitialized_returns_zero() public view {
        assertEq(module.getFee(poolId), 0);
    }

    function test_getFee_during_delay_guard_returns_starting() public {
        _initDefault();
        // same block as init — delay guard active
        assertEq(module.getFee(poolId), DEFAULT_START_FEE);
    }

    function test_getFee_at_first_post_guard_second_is_starting() public {
        _initDefault();
        vm.warp(block.timestamp + 1); // first second past DELAY_GUARD
        // At elapsed=0, timeRemaining/D = 1, squared = 1, decayAmount =
        // full feeRange, so fee = startingFee exactly. Decay begins at
        // the *next* second.
        assertEq(module.getFee(poolId), DEFAULT_START_FEE);
    }

    function test_getFee_two_seconds_in_strictly_less_than_starting() public {
        _initDefault();
        vm.warp(block.timestamp + 2);
        assertLt(module.getFee(poolId), DEFAULT_START_FEE);
    }

    function test_getFee_halfway_through_decay() public {
        _initDefault();
        vm.warp(block.timestamp + DEFAULT_SECONDS / 2); // 60s in
        uint24 fee = module.getFee(poolId);
        // At t=60s of 120s decay: elapsed = 59s (DELAY_GUARD offset),
        // timeRemaining = 61s, normalized ≈ 0.5083, squared ≈ 0.2584,
        // decayAmount ≈ 788_000 * 0.2584 ≈ 203_619.
        // fee ≈ 12_000 + 203_619 ≈ 215_619.
        assertGt(fee, 200_000);
        assertLt(fee, 230_000);
    }

    function test_getFee_near_end_of_decay() public {
        _initDefault();
        vm.warp(block.timestamp + DEFAULT_SECONDS - 1); // 1s before end
        uint24 fee = module.getFee(poolId);
        // Very close to endingFee
        assertGe(fee, DEFAULT_END_FEE);
        assertLt(fee, DEFAULT_END_FEE * 3); // well under 36_000
    }

    function test_getFee_after_decay_returns_zero() public {
        _initDefault();
        vm.warp(block.timestamp + DEFAULT_SECONDS); // exactly at end
        assertEq(module.getFee(poolId), 0);
    }

    function test_getFee_well_after_decay_returns_zero() public {
        _initDefault();
        vm.warp(block.timestamp + DEFAULT_SECONDS + 100);
        assertEq(module.getFee(poolId), 0);
    }

    function test_getFee_decay_is_monotonic_decreasing() public {
        _initDefault();
        uint256 startTs = block.timestamp;
        uint24 prev = type(uint24).max;
        for (uint256 t = 1; t < DEFAULT_SECONDS; t += 10) {
            vm.warp(startTs + t);
            uint24 fee = module.getFee(poolId);
            assertLe(fee, prev);
            prev = fee;
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Interface
    // ─────────────────────────────────────────────────────────────────

    function test_supportsInterface_wedge_mev_module() public view {
        assertTrue(module.supportsInterface(type(IWedgeMevModule).interfaceId));
        assertFalse(module.supportsInterface(bytes4(0xdeadbeef)));
    }
}
