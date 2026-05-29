// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal mock that records the arguments passed to
///         `modifyLiquidities` so tests can assert on the action
///         sequence the locker constructs. The mock does not unlock
///         the v4 PoolManager or move funds.
contract MockPositionManager {
    bytes public lastUnlockData;
    uint256 public lastDeadline;
    uint256 public callCount;
    uint256 public nextTokenId = 1;

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable {
        lastUnlockData = unlockData;
        lastDeadline = deadline;
        callCount += 1;
    }

    function setNextTokenId(uint256 id) external {
        nextTokenId = id;
    }

    /// @notice Decode helper used by tests.
    function decodeLastActions()
        external
        view
        returns (bytes memory actions, bytes[] memory params)
    {
        (actions, params) = abi.decode(lastUnlockData, (bytes, bytes[]));
    }
}
