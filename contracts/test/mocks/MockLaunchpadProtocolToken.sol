// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ILaunchpadProtocolToken} from "../../src/interfaces/ILaunchpadProtocolToken.sol";

contract MockLaunchpadProtocolToken is ILaunchpadProtocolToken {
    address public PROTOCOL_TOKEN;

    function setProtocolToken(address t) external {
        PROTOCOL_TOKEN = t;
    }
}
