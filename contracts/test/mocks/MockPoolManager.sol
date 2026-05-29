// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Minimal v4 PoolManager stub that records calls. Used by
///         `WedgeMainlineHook` unit tests to verify the hook's
///         interactions without standing up the full v4 stack.
///
///         The hook calls `initialize`, `balanceOf`, `burn`, `take`,
///         and `mint`. Each is implemented just enough to keep the
///         contract compiling and the call inspectable.
contract MockPoolManager {
    bool public initializeCalled;
    PoolKey public lastInitKey;
    uint160 public lastSqrtPriceX96;

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

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        initializeCalled = true;
        lastInitKey = key;
        lastSqrtPriceX96 = sqrtPriceX96;
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
}
