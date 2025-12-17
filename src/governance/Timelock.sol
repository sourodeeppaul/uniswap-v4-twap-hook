// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Timelock
/// @notice Timelock controller for governance actions
/// @dev Wraps OpenZeppelin's TimelockController with custom configuration
contract Timelock is TimelockController {
    /// @notice Minimum delay for proposals (2 days)
    uint256 public constant MIN_DELAY = 2 days;

    /// @notice Maximum delay for proposals (30 days)
    uint256 public constant MAX_DELAY = 30 days;

    /// @notice Constructor
    /// @param minDelay Initial minimum delay for operations
    /// @param proposers Addresses that can propose
    /// @param executors Addresses that can execute
    /// @param admin Admin address (can be address(0) to renounce admin)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {
        require(minDelay >= MIN_DELAY, "Delay too short");
        require(minDelay <= MAX_DELAY, "Delay too long");
    }

    /// @notice Schedule a batch of operations with a predecessor
    /// @param targets Target addresses
    /// @param values ETH values
    /// @param payloads Calldata payloads
    /// @param predecessor Predecessor operation (0 for none)
    /// @param salt Unique salt
    /// @param delay Delay before execution
    function scheduleBatchWithDelay(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(delay >= getMinDelay(), "Delay too short");
        scheduleBatch(targets, values, payloads, predecessor, salt, delay);
    }

    /// @notice Get operation state as string
    /// @param id Operation ID
    /// @return state Human-readable state
    function getOperationStateString(bytes32 id) external view returns (string memory state) {
        if (!isOperation(id)) return "NotScheduled";
        if (isOperationPending(id)) return "Pending";
        if (isOperationReady(id)) return "Ready";
        if (isOperationDone(id)) return "Executed";
        return "Unknown";
    }

    /// @notice Check if multiple operations are ready
    /// @param ids Array of operation IDs
    /// @return ready Array of readiness states
    function areOperationsReady(bytes32[] calldata ids) external view returns (bool[] memory ready) {
        ready = new bool[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            ready[i] = isOperationReady(ids[i]);
        }
    }

    /// @notice Get the remaining time until an operation is ready
    /// @param id Operation ID
    /// @return remaining Seconds until ready (0 if ready or not scheduled)
    function getTimeUntilReady(bytes32 id) external view returns (uint256 remaining) {
        if (!isOperation(id) || isOperationDone(id)) return 0;
        
        uint256 timestamp = getTimestamp(id);
        if (block.timestamp >= timestamp) return 0;
        
        return timestamp - block.timestamp;
    }
}
