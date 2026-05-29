// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {ILaunchpadTreasury} from "./interfaces/ILaunchpadTreasury.sol";

/// @notice Locker that custodies the three Wedge Rail LP NFTs minted at
///         launch by `WedgeRailExtension`. Has no admin, no withdraw,
///         no upgrade. Exposes a single permissionless `collectFees`
///         that sweeps accrued fees on all three positions for a token
///         to the `Launchpad`'s configured `teamFeeRecipient`.
///
///         The Rail pool is hookless, so the entire 30 bps LP fee
///         accrues to these positions on every swap and is forwarded
///         to the treasury intact (no per-swap skim, no per-recipient
///         split).
///
///         Bootstrap: `setExtension` is callable exactly once by the
///         deployer (the address that called the constructor) to wire
///         up `WedgeRailExtension`'s address. After that single call
///         the locker has no privileged caller.
contract WedgeRailLocker is IERC721Receiver, ReentrancyGuard {
    address public immutable LAUNCHPAD;
    IPositionManager public immutable POSITION_MANAGER;
    address private immutable _BOOTSTRAP;

    address private _extension;

    /// @notice Per-token holdings — the three Rail LP NFTs and the
    ///         currency pair they trade. `count` starts at zero and
    ///         increments on each `onERC721Received`; reverts at 4.
    struct Holding {
        uint256[3] tokenIds;
        Currency currency0;
        Currency currency1;
        uint8 count;
    }

    mapping(address token => Holding holding) private _holdings;

    error NotBootstrap();
    error ExtensionAlreadySet();
    error ExtensionNotSet();
    error OnlyExtension();
    error PositionCountExceeded();
    error NoHoldings();
    error TreasuryNotSet();

    event ExtensionSet(address indexed extension);
    event PositionReceived(address indexed token, uint256 indexed tokenId, uint8 positionIndex);
    event FeesCollected(address indexed token, address indexed recipient);

    constructor(address launchpad_, address positionManager_) {
        LAUNCHPAD = launchpad_;
        POSITION_MANAGER = IPositionManager(positionManager_);
        _BOOTSTRAP = msg.sender;
    }

    /// @notice One-shot setter for the `WedgeRailExtension` address.
    ///         Callable only by the constructor's caller, only once.
    function setExtension(address extension_) external {
        if (msg.sender != _BOOTSTRAP) revert NotBootstrap();
        if (_extension != address(0)) revert ExtensionAlreadySet();
        _extension = extension_;
        emit ExtensionSet(extension_);
    }

    function extension() external view returns (address) {
        return _extension;
    }

    /// @notice ERC-721 receive hook. Only accepts transfers initiated by
    ///         `WedgeRailExtension`. `data` is `abi.encode(token,
    ///         currency0, currency1)` and is consumed on the first
    ///         transfer for a token to record the currency pair.
    function onERC721Received(
        address, /* operator */
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        address ext = _extension;
        if (ext == address(0)) revert ExtensionNotSet();
        if (from != ext) revert OnlyExtension();

        (address token, Currency currency0, Currency currency1) =
            abi.decode(data, (address, Currency, Currency));

        Holding storage h = _holdings[token];
        if (h.count >= 3) revert PositionCountExceeded();
        if (h.count == 0) {
            h.currency0 = currency0;
            h.currency1 = currency1;
        }
        h.tokenIds[h.count] = tokenId;
        emit PositionReceived(token, tokenId, h.count);
        h.count += 1;

        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Permissionless. Collects accrued fees on every Rail
    ///         position for `token` and forwards them to the
    ///         Launchpad's `teamFeeRecipient`. Reverts if the locker
    ///         holds nothing for `token` or if the treasury address is
    ///         unset.
    function collectFees(address token) external nonReentrant {
        Holding storage h = _holdings[token];
        uint256 n = h.count;
        if (n == 0) revert NoHoldings();

        address treasury = ILaunchpadTreasury(LAUNCHPAD).teamFeeRecipient();
        if (treasury == address(0)) revert TreasuryNotSet();

        // Action sequence: N x DECREASE_LIQUIDITY (liquidity = 0 just
        // accrues fees) + 1 x TAKE_PAIR sweeping both currencies to
        // the treasury. All N positions share the same pair, so a
        // single TAKE_PAIR at the end drains everything.
        bytes memory actions = new bytes(n + 1);
        bytes[] memory params = new bytes[](n + 1);
        for (uint256 i = 0; i < n; i++) {
            actions[i] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
            params[i] = abi.encode(h.tokenIds[i], uint256(0), uint128(0), uint128(0), bytes(""));
        }
        actions[n] = bytes1(uint8(Actions.TAKE_PAIR));
        params[n] = abi.encode(h.currency0, h.currency1, treasury);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        emit FeesCollected(token, treasury);
    }

    /// @notice View into the per-token holding for indexers/UIs.
    function holdingsFor(address token)
        external
        view
        returns (uint256[3] memory tokenIds, Currency currency0, Currency currency1, uint8 count)
    {
        Holding storage h = _holdings[token];
        return (h.tokenIds, h.currency0, h.currency1, h.count);
    }
}
