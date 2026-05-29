// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Test} from "forge-std/Test.sol";

import {WedgeRailLocker} from "../src/WedgeRailLocker.sol";

import {MockLaunchpadTreasury} from "./mocks/MockLaunchpadTreasury.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";

contract WedgeRailLockerTest is Test {
    WedgeRailLocker internal locker;
    MockPositionManager internal positionManager;
    MockLaunchpadTreasury internal launchpad;

    address internal bootstrap;
    address internal extension;
    address internal stranger;
    address internal treasury;
    address internal token;
    Currency internal currency0;
    Currency internal currency1;

    function setUp() public {
        bootstrap = address(this);
        extension = makeAddr("extension");
        stranger = makeAddr("stranger");
        treasury = makeAddr("treasury");
        token = makeAddr("token");
        currency0 = Currency.wrap(makeAddr("currency0"));
        currency1 = Currency.wrap(makeAddr("currency1"));

        positionManager = new MockPositionManager();
        launchpad = new MockLaunchpadTreasury();
        locker = new WedgeRailLocker(address(launchpad), address(positionManager));
    }

    function _encodeData(address tok) internal view returns (bytes memory) {
        return abi.encode(tok, currency0, currency1);
    }

    function _receive(address tok, uint256 tokenId) internal {
        vm.prank(extension);
        locker.onERC721Received(extension, extension, tokenId, _encodeData(tok));
    }

    // ─────────────────────────────────────────────────────────────────
    // Construction & bootstrap
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_sets_immutables() public view {
        assertEq(locker.LAUNCHPAD(), address(launchpad));
        assertEq(address(locker.POSITION_MANAGER()), address(positionManager));
        assertEq(locker.extension(), address(0));
    }

    function test_setExtension_only_bootstrap() public {
        vm.prank(stranger);
        vm.expectRevert(WedgeRailLocker.NotBootstrap.selector);
        locker.setExtension(extension);
    }

    function test_setExtension_records_and_emits() public {
        vm.expectEmit(true, false, false, false, address(locker));
        emit WedgeRailLocker.ExtensionSet(extension);
        locker.setExtension(extension);
        assertEq(locker.extension(), extension);
    }

    function test_setExtension_only_once() public {
        locker.setExtension(extension);
        vm.expectRevert(WedgeRailLocker.ExtensionAlreadySet.selector);
        locker.setExtension(makeAddr("other"));
    }

    // ─────────────────────────────────────────────────────────────────
    // onERC721Received
    // ─────────────────────────────────────────────────────────────────

    function test_onERC721Received_reverts_before_extension_set() public {
        vm.prank(extension);
        vm.expectRevert(WedgeRailLocker.ExtensionNotSet.selector);
        locker.onERC721Received(extension, extension, 1, _encodeData(token));
    }

    function test_onERC721Received_reverts_if_from_is_stranger() public {
        locker.setExtension(extension);
        vm.prank(stranger);
        vm.expectRevert(WedgeRailLocker.OnlyExtension.selector);
        locker.onERC721Received(stranger, stranger, 1, _encodeData(token));
    }

    function test_onERC721Received_first_position_records_currencies() public {
        locker.setExtension(extension);
        vm.expectEmit(true, true, false, true, address(locker));
        emit WedgeRailLocker.PositionReceived(token, 42, 0);
        _receive(token, 42);

        (uint256[3] memory ids, Currency c0, Currency c1, uint8 count) = locker.holdingsFor(token);
        assertEq(ids[0], 42);
        assertEq(Currency.unwrap(c0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(c1), Currency.unwrap(currency1));
        assertEq(count, 1);
    }

    function test_onERC721Received_three_positions_accepted() public {
        locker.setExtension(extension);
        _receive(token, 10);
        _receive(token, 20);
        _receive(token, 30);

        (uint256[3] memory ids,,, uint8 count) = locker.holdingsFor(token);
        assertEq(ids[0], 10);
        assertEq(ids[1], 20);
        assertEq(ids[2], 30);
        assertEq(count, 3);
    }

    function test_onERC721Received_returns_selector() public {
        locker.setExtension(extension);
        vm.prank(extension);
        bytes4 ret = locker.onERC721Received(extension, extension, 1, _encodeData(token));
        assertEq(ret, IERC721Receiver.onERC721Received.selector);
    }

    function test_onERC721Received_fourth_position_reverts() public {
        locker.setExtension(extension);
        _receive(token, 10);
        _receive(token, 20);
        _receive(token, 30);
        vm.prank(extension);
        vm.expectRevert(WedgeRailLocker.PositionCountExceeded.selector);
        locker.onERC721Received(extension, extension, 40, _encodeData(token));
    }

    function test_onERC721Received_separate_tokens_independent() public {
        locker.setExtension(extension);
        address tokenB = makeAddr("tokenB");
        _receive(token, 1);
        _receive(tokenB, 2);

        (,,, uint8 countA) = locker.holdingsFor(token);
        (,,, uint8 countB) = locker.holdingsFor(tokenB);
        assertEq(countA, 1);
        assertEq(countB, 1);
    }

    // ─────────────────────────────────────────────────────────────────
    // collectFees
    // ─────────────────────────────────────────────────────────────────

    function test_collectFees_reverts_no_holdings() public {
        vm.expectRevert(WedgeRailLocker.NoHoldings.selector);
        locker.collectFees(token);
    }

    function test_collectFees_reverts_treasury_zero() public {
        locker.setExtension(extension);
        _receive(token, 1);
        // treasury not set
        vm.expectRevert(WedgeRailLocker.TreasuryNotSet.selector);
        locker.collectFees(token);
    }

    function test_collectFees_permissionless_and_calls_position_manager() public {
        locker.setExtension(extension);
        launchpad.setTeamFeeRecipient(treasury);
        _receive(token, 100);
        _receive(token, 200);
        _receive(token, 300);

        vm.prank(stranger);
        locker.collectFees(token);

        assertEq(positionManager.callCount(), 1);

        (bytes memory actions, bytes[] memory params) = positionManager.decodeLastActions();
        // 3 DECREASE_LIQUIDITY + 1 TAKE_PAIR
        assertEq(actions.length, 4);
        assertEq(uint8(actions[0]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[1]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[2]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[3]), uint8(Actions.TAKE_PAIR));
        assertEq(params.length, 4);

        // First decrease params: (tokenId=100, liquidity=0, amount0Min=0, amount1Min=0, hookData="")
        (
            uint256 tokenId,
            uint256 liquidity,
            uint128 amt0Min,
            uint128 amt1Min,
            bytes memory hookData
        ) = abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
        assertEq(tokenId, 100);
        assertEq(liquidity, 0);
        assertEq(amt0Min, 0);
        assertEq(amt1Min, 0);
        assertEq(hookData.length, 0);

        // Take pair params: (currency0, currency1, treasury)
        (Currency c0, Currency c1, address recipient) =
            abi.decode(params[3], (Currency, Currency, address));
        assertEq(Currency.unwrap(c0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(c1), Currency.unwrap(currency1));
        assertEq(recipient, treasury);
    }

    function test_collectFees_emits_FeesCollected() public {
        locker.setExtension(extension);
        launchpad.setTeamFeeRecipient(treasury);
        _receive(token, 1);

        vm.expectEmit(true, true, false, false, address(locker));
        emit WedgeRailLocker.FeesCollected(token, treasury);
        locker.collectFees(token);
    }

    function test_collectFees_partial_holdings_one_position() public {
        locker.setExtension(extension);
        launchpad.setTeamFeeRecipient(treasury);
        _receive(token, 7);

        locker.collectFees(token);
        (bytes memory actions,) = positionManager.decodeLastActions();
        // 1 DECREASE + 1 TAKE_PAIR
        assertEq(actions.length, 2);
        assertEq(uint8(actions[0]), uint8(Actions.DECREASE_LIQUIDITY));
        assertEq(uint8(actions[1]), uint8(Actions.TAKE_PAIR));
    }
}
