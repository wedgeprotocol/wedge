// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IWedgeLpLocker} from "../../src/interfaces/IWedgeLpLocker.sol";

contract MockLpLocker is IWedgeLpLocker {
    bool public placeLiquidityCalled;
    address public lastToken;
    uint256 public lastPoolSupply;

    function placeLiquidity(
        PlaceLiquidityConfig calldata, /* config */
        PoolKey calldata, /* poolKey */
        int24, /* startingTick */
        int24, /* tickSpacing */
        uint256 poolSupply,
        address token
    ) external returns (uint256) {
        placeLiquidityCalled = true;
        lastToken = token;
        lastPoolSupply = poolSupply;
        // Pull the supply in like a real locker would.
        IERC20(token).transferFrom(msg.sender, address(this), poolSupply);
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeLpLocker).interfaceId;
    }
}
