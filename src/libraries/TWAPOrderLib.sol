// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title TWAPOrderLib
/// @notice Library for TWAP order management and calculations
library TWAPOrderLib {
    using PoolIdLibrary for PoolKey;

    /// @notice Minimum chunks allowed
    uint32 internal constant MIN_CHUNKS = 2;

    /// @notice Maximum chunks allowed
    uint32 internal constant MAX_CHUNKS = 1000;

    /// @notice Minimum interval in blocks
    uint32 internal constant MIN_INTERVAL = 1;

    /// @notice Nonce for order ID generation
    uint256 private constant NONCE_SLOT = uint256(keccak256("twap.order.nonce"));

    error InvalidChunkCount();
    error InvalidInterval();
    error InvalidAmount();
    error InvalidDeadline();
    error OrderExpired();

    /// @notice Generate a unique order ID
    /// @param owner Order owner address
    /// @param poolKey Pool being traded
    /// @param nonce Unique nonce
    /// @return orderId Unique order identifier
    function generateOrderId(
        address owner,
        PoolKey memory poolKey,
        uint256 nonce
    ) internal view returns (bytes32 orderId) {
        orderId = keccak256(
            abi.encodePacked(
                owner,
                poolKey.toId(),
                nonce,
                block.chainid
            )
        );
    }

    /// @notice Calculate amount per chunk
    /// @param totalAmount Total order amount
    /// @param numChunks Number of chunks
    /// @return chunkAmount Amount per chunk
    function calculateChunkAmount(
        uint256 totalAmount,
        uint32 numChunks
    ) internal pure returns (uint256 chunkAmount) {
        if (numChunks == 0) revert InvalidChunkCount();
        chunkAmount = totalAmount / numChunks;
    }

    /// @notice Calculate remaining amount for last chunk (handles rounding)
    /// @param totalAmount Total order amount
    /// @param numChunks Number of chunks
    /// @param chunksExecuted Chunks already executed
    /// @return remainingAmount Amount remaining
    function calculateRemainingAmount(
        uint256 totalAmount,
        uint32 numChunks,
        uint32 chunksExecuted
    ) internal pure returns (uint256 remainingAmount) {
        if (numChunks == 0 || chunksExecuted >= numChunks) return 0;
        
        uint256 chunkAmount = totalAmount / numChunks;
        uint256 executedAmount = chunkAmount * chunksExecuted;
        remainingAmount = totalAmount - executedAmount;
    }

    /// @notice Get amount for next chunk execution
    /// @param totalAmount Total order amount
    /// @param numChunks Number of chunks
    /// @param chunksExecuted Chunks already executed
    /// @return nextChunkAmount Amount for next execution
    function getNextChunkAmount(
        uint256 totalAmount,
        uint32 numChunks,
        uint32 chunksExecuted
    ) internal pure returns (uint256 nextChunkAmount) {
        if (chunksExecuted >= numChunks) return 0;
        
        // Last chunk gets any remaining dust
        if (chunksExecuted == numChunks - 1) {
            return calculateRemainingAmount(totalAmount, numChunks, chunksExecuted);
        }
        
        return calculateChunkAmount(totalAmount, numChunks);
    }

    /// @notice Validate order parameters
    /// @param params Order parameters to validate
    /// @param config System configuration
    function validateOrderParams(
        TWAPTypes.OrderParams memory params,
        TWAPTypes.Config memory config
    ) internal view {
        // Validate amount
        if (params.amountIn == 0) revert InvalidAmount();
        
        uint256 chunkSize = params.amountIn / params.numChunks;
        if (chunkSize < config.minChunkSize) {
            revert InvalidAmount();
        }
        if (config.maxChunkSize > 0 && chunkSize > config.maxChunkSize) {
            revert InvalidAmount();
        }
        
        // Validate chunks
        if (params.numChunks < MIN_CHUNKS || params.numChunks > MAX_CHUNKS) {
            revert InvalidChunkCount();
        }
        
        // Validate interval
        if (params.intervalBlocks < config.minIntervalBlocks) {
            revert InvalidInterval();
        }
        if (params.intervalBlocks > config.maxIntervalBlocks) {
            revert InvalidInterval();
        }
        
        // Validate deadline
        if (params.deadline <= block.timestamp) {
            revert InvalidDeadline();
        }
        
        // Validate total duration
        uint256 totalBlocks = uint256(params.numChunks) * uint256(params.intervalBlocks);
        if (totalBlocks > config.maxOrderDuration) {
            revert InvalidInterval();
        }
        
        // Validate slippage
        if (params.maxSlippageBps > config.maxSlippageBps) {
            revert TWAPTypes.SlippageExceeded(config.maxSlippageBps, params.maxSlippageBps);
        }
    }

    /// @notice Check if order can be executed
    /// @param order The order to check
    /// @return canExecute Whether order can be executed
    /// @return blocksUntil Blocks until next execution (0 if ready)
    function canExecute(
        TWAPTypes.Order memory order
    ) internal view returns (bool canExecute, uint256 blocksUntil) {
        // Check status
        if (order.status != TWAPTypes.OrderStatus.Active && 
            order.status != TWAPTypes.OrderStatus.Pending) {
            return (false, 0);
        }
        
        // Check expiry
        if (block.timestamp > order.params.deadline) {
            return (false, 0);
        }
        
        // Check if all chunks executed
        if (order.executionState.chunksExecuted >= order.params.numChunks) {
            return (false, 0);
        }
        
        // Check interval
        uint256 nextExecutionBlock = order.executionState.lastExecutionBlock + 
            order.params.intervalBlocks;
        
        if (block.number >= nextExecutionBlock) {
            return (true, 0);
        }
        
        return (false, nextExecutionBlock - block.number);
    }

    /// @notice Check if order is expired
    /// @param order The order to check
    /// @return isExpired Whether order has expired
    function isExpired(TWAPTypes.Order memory order) internal view returns (bool isExpired) {
        isExpired = block.timestamp > order.params.deadline;
    }

    /// @notice Check if order is complete
    /// @param order The order to check
    /// @return isComplete Whether all chunks are executed
    function isComplete(TWAPTypes.Order memory order) internal pure returns (bool isComplete) {
        isComplete = order.executionState.chunksExecuted >= order.params.numChunks;
    }

    /// @notice Calculate progress percentage
    /// @param order The order to check
    /// @return progressBps Progress in basis points (0-10000)
    function getProgress(TWAPTypes.Order memory order) internal pure returns (uint256 progressBps) {
        if (order.params.numChunks == 0) return 0;
        progressBps = (uint256(order.executionState.chunksExecuted) * 10_000) / 
            uint256(order.params.numChunks);
    }

    /// @notice Update execution state after chunk execution
    /// @param state Current execution state
    /// @param chunkAmountIn Amount of input used
    /// @param chunkAmountOut Amount of output received
    /// @param gasUsed Gas consumed
    /// @return newState Updated execution state
    function updateExecutionState(
        TWAPTypes.ExecutionState memory state,
        uint256 chunkAmountIn,
        uint256 chunkAmountOut,
        uint256 gasUsed
    ) internal view returns (TWAPTypes.ExecutionState memory newState) {
        newState.chunksExecuted = state.chunksExecuted + 1;
        newState.amountInRemaining = state.amountInRemaining - chunkAmountIn;
        newState.amountOutAccumulated = state.amountOutAccumulated + chunkAmountOut;
        newState.lastExecutionBlock = block.number;
        newState.totalGasUsed = state.totalGasUsed + gasUsed;
        
        // Update weighted average price
        uint256 totalIn = (state.amountOutAccumulated > 0) 
            ? state.amountInRemaining + chunkAmountIn 
            : chunkAmountIn;
        
        if (newState.amountOutAccumulated > 0) {
            newState.averagePrice = (totalIn * 1e18) / newState.amountOutAccumulated;
        }
    }

    /// @notice Create initial execution state
    /// @param amountIn Total input amount
    /// @return state Initial execution state
    function createInitialState(
        uint256 amountIn
    ) internal view returns (TWAPTypes.ExecutionState memory state) {
        state.chunksExecuted = 0;
        state.amountInRemaining = amountIn;
        state.amountOutAccumulated = 0;
        state.lastExecutionBlock = block.number;
        state.averagePrice = 0;
        state.totalGasUsed = 0;
    }
}
