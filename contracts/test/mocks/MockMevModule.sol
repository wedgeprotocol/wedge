// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeMevModule} from "../../src/interfaces/IWedgeMevModule.sol";

contract MockMevModule is IWedgeMevModule {
    bool public initializeCalled;

    function initialize(
        PoolKey calldata,
        /* poolKey */
        bytes calldata /* data */
    )
        external
    {
        initializeCalled = true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeMevModule).interfaceId;
    }
}
