// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Optional per-launch extension. Extensions receive a share of
///         the launched token's supply and an optional ETH msgValue at
///         deploy time and can do whatever they like with both — open a
///         second pool, vest a portion to the team, perform a dev-buy,
///         etc.
///
///         If `requiresProtocolToken()` returns true, the Launchpad
///         refuses to run the extension while its `PROTOCOL_TOKEN` is
///         still the zero address. This prevents bootstrap-order
///         mistakes (the Protocol Rail extension must not be invoked
///         before the protocol token has been set).
interface IWedgeExtension {
    error InvalidMsgValue();

    function receiveTokens(address token, uint256 extensionSupply, bytes calldata extensionData)
        external
        payable;

    function requiresProtocolToken() external view returns (bool);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
