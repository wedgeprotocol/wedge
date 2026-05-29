// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LaunchToken} from "./LaunchToken.sol";

/// @notice CREATE2 wrapper that deploys a `LaunchToken` from a
///         deterministic salt. Lives as a library so the Launchpad's
///         bytecode does not include the LaunchToken bytecode (which
///         would inflate the factory contract size and tie its address
///         to the token implementation).
library LaunchDeployer {
    struct TokenConfig {
        address admin;
        string name;
        string symbol;
        bytes32 salt;
        string image;
        string metadata;
        string context;
        bool renounceAtDeploy;
    }

    function deploy(TokenConfig memory config, uint256 supply)
        external
        returns (address tokenAddress)
    {
        LaunchToken token = new LaunchToken{salt: keccak256(abi.encode(config.admin, config.salt))}(
            config.name,
            config.symbol,
            supply,
            config.admin,
            config.image,
            config.metadata,
            config.context,
            config.renounceAtDeploy
        );
        return address(token);
    }
}
