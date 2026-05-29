// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWedgeExtension} from "../../src/interfaces/IWedgeExtension.sol";

contract MockExtension is IWedgeExtension {
    bool public immutable REQUIRES_PROTOCOL_TOKEN;

    bool public receiveTokensCalled;
    address public lastToken;
    uint256 public lastSupply;
    uint256 public lastMsgValue;

    constructor(bool requiresProtocol) {
        REQUIRES_PROTOCOL_TOKEN = requiresProtocol;
    }

    function receiveTokens(
        address token,
        uint256 extensionSupply,
        bytes calldata /* data */
    )
        external
        payable
    {
        receiveTokensCalled = true;
        lastToken = token;
        lastSupply = extensionSupply;
        lastMsgValue = msg.value;
        if (extensionSupply > 0) {
            IERC20(token).transferFrom(msg.sender, address(this), extensionSupply);
        }
    }

    function requiresProtocolToken() external view returns (bool) {
        return REQUIRES_PROTOCOL_TOKEN;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IWedgeExtension).interfaceId;
    }
}
