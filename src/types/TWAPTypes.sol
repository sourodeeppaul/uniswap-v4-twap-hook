// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @title TWAPTypes
/// @notice Shared type definitions for the TWAP Hook system
library TWAPTypes {
    // ============ Enums ============

    /// @notice Order status enumeration
    enum OrderStatus {
        None,       // Order does not exist
        Pending,    // Order created, awaiting first execution
        Active,     // Order is being executed
        Completed,  // Order fully executed
        Cancelled,  // Order cancelled by user
        Expired,    // Order expired before completion
        Failed      // Order failed due to error
    }

    /// @notice Execution result status
    enum ExecutionResult {
        Success,            // Chunk executed successfully
        InsufficientLiquidity,  // Not enough liquidity
        SlippageExceeded,   // Slippage limit exceeded
        PriceDeviation,     // Price deviated too much from TWAP
        CircuitBreakerTriggered,  // Emergency stop activated
        RateLimited,        // Rate limit exceeded
        Expired             // Order expired during execution
    }

    // ============ Structs ============

    /// @notice Parameters for creating a new TWAP order
    /// @param poolKey The Uniswap v4 pool to trade in
    /// @param zeroForOne Direction of the swap (true = token0 -> token1)
    /// @param amountIn Total amount of input tokens
    /// @param minAmountOut Minimum total output expected (slippage protection)
    /// @param numChunks Number of chunks to split the order into
    /// @param intervalBlocks Number of blocks between each chunk execution
    /// @param maxSlippageBps Maximum slippage per chunk in basis points
    /// @param deadline Timestamp after which the order expires
    /// @param recipient Address to receive the output tokens
    struct OrderParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint256 amountIn;
        uint256 minAmountOut;
        uint32 numChunks;
        uint32 intervalBlocks;
        uint16 maxSlippageBps;
        uint256 deadline;
        address recipient;
    }

    /// @notice Full order state stored on-chain
    /// @param id Unique order identifier
    /// @param owner Address that created the order
    /// @param params Original order parameters
    /// @param status Current order status
    /// @param executionState Current execution progress
    /// @param createdAt Block number when order was created
    /// @param updatedAt Block number of last update
    struct Order {
        bytes32 id;
        address owner;
        OrderParams params;
        OrderStatus status;
        ExecutionState executionState;
        uint256 createdAt;
        uint256 updatedAt;
    }

    /// @notice Tracks execution progress of an order
    /// @param chunksExecuted Number of chunks already executed
    /// @param amountInRemaining Remaining input tokens to swap
    /// @param amountOutAccumulated Total output tokens received so far
    /// @param lastExecutionBlock Block number of last execution
    /// @param averagePrice Weighted average execution price
    /// @param totalGasUsed Total gas consumed by executions
    struct ExecutionState {
        uint32 chunksExecuted;
        uint256 amountInRemaining;
        uint256 amountOutAccumulated;
        uint256 lastExecutionBlock;
        uint256 averagePrice;
        uint256 totalGasUsed;
    }

    /// @notice Price point from oracle
    /// @param price The price value (scaled by 1e18)
    /// @param timestamp When the price was recorded
    /// @param blockNumber Block number of the price
    /// @param confidence Confidence score (0-10000 bps)
    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        uint256 blockNumber;
        uint16 confidence;
    }

    /// @notice TWAP calculation result
    /// @param twapPrice Time-weighted average price
    /// @param startBlock Start block of TWAP window
    /// @param endBlock End block of TWAP window
    /// @param numObservations Number of price observations used
    struct TWAPResult {
        uint256 twapPrice;
        uint256 startBlock;
        uint256 endBlock;
        uint32 numObservations;
    }

    /// @notice Commit data for commit-reveal scheme
    /// @param commitment Hash of order parameters + salt
    /// @param commitBlock Block when commitment was made
    /// @param revealed Whether the commitment has been revealed
    struct Commitment {
        bytes32 commitment;
        uint256 commitBlock;
        bool revealed;
    }

    /// @notice Configuration parameters for the TWAP system
    /// @param minChunkSize Minimum size per chunk
    /// @param maxChunkSize Maximum size per chunk
    /// @param minIntervalBlocks Minimum blocks between executions
    /// @param maxIntervalBlocks Maximum blocks between executions
    /// @param maxOrderDuration Maximum order duration in blocks
    /// @param commitRevealDelay Blocks to wait between commit and reveal
    /// @param maxSlippageBps Maximum allowed slippage in bps
    /// @param protocolFeeBps Protocol fee in basis points
    struct Config {
        uint256 minChunkSize;
        uint256 maxChunkSize;
        uint32 minIntervalBlocks;
        uint32 maxIntervalBlocks;
        uint32 maxOrderDuration;
        uint32 commitRevealDelay;
        uint16 maxSlippageBps;
        uint16 protocolFeeBps;
    }

    /// @notice Rate limit configuration
    /// @param maxAmountPerWindow Maximum amount per time window
    /// @param windowDuration Duration of the rate limit window
    /// @param cooldownPeriod Cooldown after hitting limit
    struct RateLimitConfig {
        uint256 maxAmountPerWindow;
        uint256 windowDuration;
        uint256 cooldownPeriod;
    }

    /// @notice Execution chunk details
    /// @param orderId The order this chunk belongs to
    /// @param chunkIndex Index of this chunk (0-indexed)
    /// @param amountIn Input amount for this chunk
    /// @param amountOut Output amount received
    /// @param executionBlock Block when executed
    /// @param gasUsed Gas consumed by execution
    struct ChunkExecution {
        bytes32 orderId;
        uint32 chunkIndex;
        uint256 amountIn;
        uint256 amountOut;
        uint256 executionBlock;
        uint256 gasUsed;
    }

    // ============ Events ============

    /// @notice Emitted when a new order is created
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed owner,
        PoolKey poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint32 numChunks,
        uint32 intervalBlocks
    );

    /// @notice Emitted when an order chunk is executed
    event ChunkExecuted(
        bytes32 indexed orderId,
        uint32 indexed chunkIndex,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionPrice
    );

    /// @notice Emitted when an order is completed
    event OrderCompleted(
        bytes32 indexed orderId,
        uint256 totalAmountIn,
        uint256 totalAmountOut,
        uint256 averagePrice
    );

    /// @notice Emitted when an order is cancelled
    event OrderCancelled(
        bytes32 indexed orderId,
        address indexed owner,
        uint256 amountRefunded
    );

    /// @notice Emitted when an order expires
    event OrderExpired(
        bytes32 indexed orderId,
        uint256 amountInRemaining,
        uint256 amountOutAccumulated
    );

    /// @notice Emitted when configuration is updated
    event ConfigUpdated(
        uint256 minChunkSize,
        uint256 maxChunkSize,
        uint32 minIntervalBlocks,
        uint32 maxIntervalBlocks
    );

    // ============ Errors ============

    /// @notice Order does not exist
    error OrderNotFound(bytes32 orderId);

    /// @notice Order is not in expected status
    error InvalidOrderStatus(bytes32 orderId, OrderStatus expected, OrderStatus actual);

    /// @notice Caller is not authorized
    error Unauthorized(address caller, address expected);

    /// @notice Invalid order parameters
    error InvalidOrderParams(string reason);

    /// @notice Order has expired
    error OrderHasExpired(bytes32 orderId);

    /// @notice Not enough time has passed for execution
    error ExecutionTooEarly(bytes32 orderId, uint256 nextExecutionBlock);

    /// @notice Slippage limit exceeded
    error SlippageExceeded(uint256 expected, uint256 actual);

    /// @notice Price deviation too high
    error PriceDeviationTooHigh(uint256 currentPrice, uint256 twapPrice, uint256 maxDeviation);

    /// @notice Circuit breaker is active
    error CircuitBreakerActive();

    /// @notice Rate limit exceeded
    error RateLimitExceeded(address user, uint256 amount, uint256 limit);

    /// @notice Commitment not found or already revealed
    error InvalidCommitment(bytes32 commitment);

    /// @notice Reveal too early
    error RevealTooEarly(uint256 currentBlock, uint256 allowedBlock);

    /// @notice Zero address provided
    error ZeroAddress();

    /// @notice Zero amount provided
    error ZeroAmount();

    /// @notice Deadline passed
    error DeadlinePassed(uint256 deadline, uint256 currentTime);
}
