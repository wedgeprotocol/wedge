// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal v4 PositionManager stub. Records calls to
///         `modifyLiquidities`, exposes `nextTokenId` so tests can
///         predict position IDs, and records `safeTransferFrom` so
///         tests can verify NFT hand-off to the locker without
///         standing up a real ERC-721.
contract MockPositionManager {
    bytes public lastUnlockData;
    uint256 public lastDeadline;
    uint256 public callCount;
    uint256 public nextTokenId = 1;

    bool public safeTransferFromCalled;
    address public lastTransferFrom;
    address public lastTransferTo;
    uint256 public lastTransferTokenId;
    bytes public lastTransferData;
    uint256 public safeTransferFromCallCount;

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable {
        lastUnlockData = unlockData;
        lastDeadline = deadline;
        callCount += 1;
    }

    function setNextTokenId(uint256 id) external {
        nextTokenId = id;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data)
        external
    {
        safeTransferFromCalled = true;
        lastTransferFrom = from;
        lastTransferTo = to;
        lastTransferTokenId = tokenId;
        lastTransferData = data;
        safeTransferFromCallCount += 1;
    }

    function decodeLastActions()
        external
        view
        returns (bytes memory actions, bytes[] memory params)
    {
        (actions, params) = abi.decode(lastUnlockData, (bytes, bytes[]));
    }
}
