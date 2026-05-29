// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal view of the `Launchpad` for peripherals that need
///         to look up the protocol token (WEDGE) address.
interface ILaunchpadProtocolToken {
    function PROTOCOL_TOKEN() external view returns (address);
}
