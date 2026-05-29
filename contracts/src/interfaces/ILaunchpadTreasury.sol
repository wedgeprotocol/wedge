// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal view of the `Launchpad` that other Wedge contracts
///         use to look up the protocol treasury address. Decoupled from
///         the full `Launchpad` ABI so peripheral contracts (e.g. the
///         Wedge Rail locker) don't import the factory directly.
interface ILaunchpadTreasury {
    function teamFeeRecipient() external view returns (address);
}
