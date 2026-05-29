// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Two-tier access control: a single owner plus an extensible
///         allowlist of admin operators. Owner is the high-privilege
///         account (deprecate factory, rotate treasury). Admins handle
///         day-to-day operational mutations.
interface IOwnerAdmins {
    error Unauthorized();

    event SetAdmin(address indexed admin, bool enabled);

    function admins(address admin) external view returns (bool);
    function setAdmin(address admin, bool enabled) external;
}
