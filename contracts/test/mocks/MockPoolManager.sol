// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Minimal v4 PoolManager stub that records calls. Used by
///         hook + extension unit tests so we don't have to stand up
///         the full v4 stack.
///
///         Supports: `initialize`, ERC-6909 `balanceOf` / `mint` /
///         `burn`, `take`, and `extsload` so `StateLibrary.getSlot0`
///         returns the slot0 word tests pre-seed via `setSlot0`.
contract MockPoolManager {
    bool public initializeCalled;
    PoolKey public lastInitKey;
    uint160 public lastSqrtPriceX96;
    uint256 public initializeCallCount;

    mapping(address owner => mapping(uint256 id => uint256 balance)) private _balances;

    bool public burnCalled;
    address public lastBurnOwner;
    uint256 public lastBurnId;
    uint256 public lastBurnAmount;

    bool public takeCalled;
    Currency public lastTakeCurrency;
    address public lastTakeTo;
    uint256 public lastTakeAmount;

    bool public mintCalled;
    address public lastMintTo;
    uint256 public lastMintId;
    uint256 public lastMintAmount;

    // Per-poolId Slot0 state for getSlot0 mocking. The key is the
    // *derived* storage slot from `StateLibrary._getPoolStateSlot`,
    // matching `keccak256(poolId, POOLS_SLOT=6)`.
    mapping(bytes32 stateSlot => uint160 sqrtPriceX96) private _slot0SqrtPrice;
    mapping(bytes32 stateSlot => int24 tick) private _slot0Tick;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        initializeCalled = true;
        lastInitKey = key;
        lastSqrtPriceX96 = sqrtPriceX96;
        initializeCallCount += 1;
        return 0;
    }

    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return _balances[owner][id];
    }

    function setBalanceOf(address owner, uint256 id, uint256 amount) external {
        _balances[owner][id] = amount;
    }

    function burn(address from, uint256 id, uint256 amount) external {
        burnCalled = true;
        lastBurnOwner = from;
        lastBurnId = id;
        lastBurnAmount = amount;
        _balances[from][id] -= amount;
    }

    function take(Currency currency, address to, uint256 amount) external {
        takeCalled = true;
        lastTakeCurrency = currency;
        lastTakeTo = to;
        lastTakeAmount = amount;
    }

    function mint(address to, uint256 id, uint256 amount) external {
        mintCalled = true;
        lastMintTo = to;
        lastMintId = id;
        lastMintAmount = amount;
        _balances[to][id] += amount;
    }

    /// @dev Tests call this to pre-seed the WEDGE/WETH spot used by
    ///      the rail extension via `getSlot0`.
    function setSlot0(PoolId poolId, uint160 sqrtPriceX96, int24 tick) external {
        bytes32 stateSlot = _stateSlot(poolId);
        _slot0SqrtPrice[stateSlot] = sqrtPriceX96;
        _slot0Tick[stateSlot] = tick;
    }

    /// @dev `StateLibrary.getSlot0` reads via `extsload(stateSlot)`
    ///      and decodes the packed (sqrtPriceX96, tick, protocolFee,
    ///      lpFee) word. We only need the first two fields.
    function extsload(bytes32 slot) external view returns (bytes32) {
        uint160 sqrtPriceX96 = _slot0SqrtPrice[slot];
        int24 tick = _slot0Tick[slot];
        // Pack: sqrtPriceX96 in low 160 bits, tick (24 bits) at bit 160.
        uint256 packed = uint256(sqrtPriceX96);
        packed |= uint256(uint24(tick)) << 160;
        return bytes32(packed);
    }

    function _stateSlot(PoolId poolId) internal pure returns (bytes32) {
        // Matches StateLibrary._getPoolStateSlot:
        //   keccak256(abi.encodePacked(poolId, POOLS_SLOT=6))
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(uint256(6))));
    }
}
