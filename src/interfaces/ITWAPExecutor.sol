// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title ITWAPExecutor
/// @notice Interface for the TWAP Executor - handles trade execution logic
interface ITWAPExecutor {
    // ============ Execution ============

    /// @notice Execute a single chunk of an order
    /// @param orderId The order to execute
    /// @return result The execution result
    /// @return amountOut The output amount received
    function executeChunk(bytes32 orderId) external returns (TWAPTypes.ExecutionResult result, uint256 amountOut);

    /// @notice Execute multiple order chunks in a batch
    /// @param orderIds Array of order IDs to execute
    /// @return results Array of execution results
    /// @return amountsOut Array of output amounts
    function batchExecuteChunks(bytes32[] calldata orderIds)
        external
        returns (TWAPTypes.ExecutionResult[] memory results, uint256[] memory amountsOut);

    /// @notice Simulate execution without state changes
    /// @param orderId The order to simulate
    /// @return expectedOut Expected output amount
    /// @return priceImpact Expected price impact in bps
    function simulateExecution(bytes32 orderId) external view returns (uint256 expectedOut, uint256 priceImpact);

    // ============ Execution Queries ============

    /// @notice Check if an order chunk can be executed
    /// @param orderId The order to check
    /// @return canExecute Whether execution is possible
    /// @return blockUntilExecution Blocks until next execution (0 if ready)
    function canExecute(bytes32 orderId) external view returns (bool canExecute, uint256 blockUntilExecution);

    /// @notice Get the next chunk amount for an order
    /// @param orderId The order ID
    /// @return amount The next chunk amount
    function getNextChunkAmount(bytes32 orderId) external view returns (uint256 amount);

    /// @notice Get execution history for an order
    /// @param orderId The order ID
    /// @return executions Array of chunk execution details
    function getExecutionHistory(bytes32 orderId)
        external
        view
        returns (TWAPTypes.ChunkExecution[] memory executions);

    // ============ Price Calculations ============

    /// @notice Calculate expected output for a given input
    /// @param poolKey The pool to query
    /// @param zeroForOne Swap direction
    /// @param amountIn Input amount
    /// @return amountOut Expected output amount
    function calculateExpectedOutput(PoolKey memory poolKey, bool zeroForOne, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice Get current pool price
    /// @param poolKey The pool to query
    /// @return price Current price
    function getCurrentPrice(PoolKey calldata poolKey) external view returns (uint256 price);

    // ============ Configuration ============

    /// @notice Set the maximum gas per execution
    /// @param maxGas Maximum gas limit
    function setMaxGasPerExecution(uint256 maxGas) external;

    /// @notice Set the keeper reward percentage
    /// @param rewardBps Reward in basis points
    function setKeeperReward(uint16 rewardBps) external;

    /// @notice Get executor configuration
    /// @return maxGas Maximum gas per execution
    /// @return keeperRewardBps Keeper reward in bps
    function getExecutorConfig() external view returns (uint256 maxGas, uint16 keeperRewardBps);

    // ============ Events ============

    event ChunkExecuted(
        bytes32 indexed orderId,
        uint32 chunkIndex,
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasUsed,
        address indexed keeper
    );
    event ExecutionFailed(bytes32 indexed orderId, TWAPTypes.ExecutionResult reason);
    event KeeperRewarded(address indexed keeper, uint256 reward);
    event MaxGasUpdated(uint256 newMaxGas);
    event KeeperRewardUpdated(uint16 newRewardBps);
}
