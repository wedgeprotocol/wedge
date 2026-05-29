// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title LaunchToken
/// @notice ERC-20 used by every token launched through Wedge.
///
///         Boring by intent:
///           - Total supply is minted once in the constructor and never grows.
///             No `_mint` is reachable from any external function.
///           - No bridge mint / burn (Wedge is Base-only).
///           - No inflation, no rebasing, no pool-control hooks.
///           - No blacklist, pause, transfer tax, or per-address slippage.
///
///         Creator-facing surface (admin-gated until renounced):
///           - `updateAdmin` — rotate `_admin` (e.g. to a multisig).
///           - `updateImage` — correct an image URL after launch.
///           - `updateMetadata` — update the metadata blob.
///           - `renounceAdmin` — one-way: sets `_admin` to address(0).
///             After renouncement, the four admin-gated functions all revert.
///
///         `_originalAdmin` is immutable. `verify()` may be called once by
///         `_originalAdmin` only, recording a permanent on-chain signal that
///         the original deployer has acknowledged the token. Rotating
///         `_admin` does NOT transfer the right to `verify()`.
contract LaunchToken is ERC20, ERC20Permit, ERC20Votes, ERC20Burnable {
    string public constant PROTOCOL = "Wedge";

    error NotAdmin();
    error NotOriginalAdmin();
    error AlreadyVerified();

    address private immutable _originalAdmin;
    address private _admin;

    string private _image;
    string private _metadata;
    string private _context;

    bool private _verified;

    event Verified(address indexed admin, address indexed token);
    event UpdateAdmin(address indexed oldAdmin, address indexed newAdmin);
    event UpdateImage(string image);
    event UpdateMetadata(string metadata);
    event AdminRenounced(address indexed previousAdmin);

    /// @param name_     ERC-20 name.
    /// @param symbol_   ERC-20 symbol.
    /// @param maxSupply_ Total supply minted to `msg.sender` (the deployer / Launchpad factory).
    /// @param admin_    Initial admin. Receives `_admin` and `_originalAdmin`.
    /// @param image_    Initial image URL (HTTPS or IPFS).
    /// @param metadata_ Initial metadata blob (free-form, typically JSON).
    /// @param context_  Free-form context string set once at deploy and not updateable.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address admin_,
        string memory image_,
        string memory metadata_,
        string memory context_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _originalAdmin = admin_;
        _admin = admin_;
        _image = image_;
        _metadata = metadata_;
        _context = context_;

        _mint(msg.sender, maxSupply_);
    }

    // -------------------------------------------------------------------------
    // Admin-gated setters (revert after renouncement)
    // -------------------------------------------------------------------------

    /// @notice Rotate `_admin` to a new address (e.g. a multisig).
    /// @dev Reverts after `renounceAdmin()` (admin is the zero address).
    function updateAdmin(address admin_) external {
        if (msg.sender != _admin) revert NotAdmin();
        address oldAdmin = _admin;
        _admin = admin_;
        emit UpdateAdmin(oldAdmin, admin_);
    }

    /// @notice Update the token image URL.
    function updateImage(string memory image_) external {
        if (msg.sender != _admin) revert NotAdmin();
        _image = image_;
        emit UpdateImage(image_);
    }

    /// @notice Update the token metadata blob.
    function updateMetadata(string memory metadata_) external {
        if (msg.sender != _admin) revert NotAdmin();
        _metadata = metadata_;
        emit UpdateMetadata(metadata_);
    }

    /// @notice Permanently renounce admin. Sets `_admin` to address(0).
    /// @dev After this call, `updateAdmin`, `updateImage`, `updateMetadata`,
    ///      and `renounceAdmin` all revert (the admin check sees address(0)
    ///      and `msg.sender` is never address(0) under EOA / contract calls).
    function renounceAdmin() external {
        if (msg.sender != _admin) revert NotAdmin();
        address previousAdmin = _admin;
        _admin = address(0);
        emit AdminRenounced(previousAdmin);
    }

    // -------------------------------------------------------------------------
    // One-shot verification (originalAdmin only, before renouncement irrelevant)
    // -------------------------------------------------------------------------

    /// @notice Records a one-time signal that the original deployer
    ///         acknowledges this token. Callable once by `_originalAdmin`.
    /// @dev Rotating `_admin` does NOT transfer the right to `verify()`.
    function verify() external {
        if (msg.sender != _originalAdmin) revert NotOriginalAdmin();
        if (_verified) revert AlreadyVerified();
        _verified = true;
        emit Verified(msg.sender, address(this));
    }

    function isVerified() external view returns (bool) {
        return _verified;
    }

    // -------------------------------------------------------------------------
    // Read-only views
    // -------------------------------------------------------------------------

    function admin() external view returns (address) {
        return _admin;
    }

    function originalAdmin() external view returns (address) {
        return _originalAdmin;
    }

    function imageUrl() external view returns (string memory) {
        return _image;
    }

    function metadata() external view returns (string memory) {
        return _metadata;
    }

    function context() external view returns (string memory) {
        return _context;
    }

    /// @notice Convenience accessor returning everything a frontend usually needs.
    function allData()
        external
        view
        returns (
            address originalAdmin_,
            address admin_,
            string memory image_,
            string memory metadata_,
            string memory context_
        )
    {
        return (_originalAdmin, _admin, _image, _metadata, _context);
    }

    // -------------------------------------------------------------------------
    // ERC-20 + ERC20Votes plumbing
    // -------------------------------------------------------------------------

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner_) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner_);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC5805).interfaceId;
    }
}
