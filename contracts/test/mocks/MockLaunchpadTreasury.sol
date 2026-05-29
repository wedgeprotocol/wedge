// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ILaunchpadTreasury} from "../../src/interfaces/ILaunchpadTreasury.sol";

contract MockLaunchpadTreasury is ILaunchpadTreasury {
    address public teamFeeRecipient;

    function setTeamFeeRecipient(address recipient) external {
        teamFeeRecipient = recipient;
    }
}
