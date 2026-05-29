// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeHook} from "../../src/interfaces/IWedgeHook.sol";

contract MockHook is IWedgeHook {
    bool public initializePoolCalled;
    bool public initializeMevModuleCalled;
    PoolKey public lastPoolKey;
    address public lastLocker;
    address public lastMevModule;

    function initializePool(
        address tokenLaunched,
        address pairedToken,
        int24 tickIfToken0IsLaunched,
        int24, /* tickSpacing */
        address locker,
        address mevModule,
        bytes calldata /* poolData */
    ) external returns (PoolKey memory poolKey) {
        initializePoolCalled = true;
        lastLocker = locker;
        lastMevModule = mevModule;
        bool token0IsLaunched = tokenLaunched < pairedToken;
        poolKey = PoolKey({
            currency0: Currency.wrap(token0IsLaunched ? tokenLaunched : pairedToken),
            currency1: Currency.wrap(token0IsLaunched ? pairedToken : tokenLaunched),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });
        lastPoolKey = poolKey;
        // silence unused variable warning
        tickIfToken0IsLaunched;
    }

    function initializeMevModule(
        PoolKey calldata,
        /* poolKey */
        bytes calldata /* data */
    )
        external
    {
        initializeMevModuleCalled = true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeHook).interfaceId;
    }
}
