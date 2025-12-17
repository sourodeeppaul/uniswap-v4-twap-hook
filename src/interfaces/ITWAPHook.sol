// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title ITWAPHook
/// @notice Interface for the main TWAP Hook contract
interface ITWAPHook {
    // ============ Order Management ============

    /// @notice Create a new TWAP order
    /// @param params Order parameters
    /// @return orderId Unique identifier for the created order
    function createOrder(TWAPTypes.OrderParams calldata params) external payable returns (bytes32 orderId);

    /// @notice Cancel an existing order
    /// @param orderId The order to cancel
    function cancelOrder(bytes32 orderId) external;

    /// @notice Get order details
    /// @param orderId The order to query
    /// @return order The full order details
    function getOrder(bytes32 orderId) external view returns (TWAPTypes.Order memory order);

    /// @notice Get all orders for a user
    /// @param user The user address
    /// @return orderIds Array of order IDs
    function getUserOrders(address user) external view returns (bytes32[] memory orderIds);

    /// @notice Check if an order can be executed
    /// @param orderId The order to check
    /// @return canExecute Whether the order can be executed now
    /// @return reason Reason if cannot execute
    function canExecuteOrder(bytes32 orderId) external view returns (bool canExecute, string memory reason);

    // ============ Execution ============

    /// @notice Execute the next chunk of an order (keeper function)
    /// @param orderId The order to execute
    /// @return result The execution result
    function executeOrder(bytes32 orderId) external returns (TWAPTypes.ExecutionResult result);

    /// @notice Batch execute multiple orders
    /// @param orderIds Array of orders to execute
    /// @return results Array of execution results
    function batchExecuteOrders(bytes32[] calldata orderIds)
        external
        returns (TWAPTypes.ExecutionResult[] memory results);

    /// @notice Get orders ready for execution
    /// @param maxOrders Maximum number of orders to return
    /// @return orderIds Array of executable order IDs
    function getExecutableOrders(uint256 maxOrders) external view returns (bytes32[] memory orderIds);

    // ============ Configuration ============

    /// @notice Get the current configuration
    /// @return config The current configuration
    function getConfig() external view returns (TWAPTypes.Config memory config);

    /// @notice Update configuration (governance only)
    /// @param newConfig New configuration
    function updateConfig(TWAPTypes.Config calldata newConfig) external;

    // ============ View Functions ============

    /// @notice Get the pool manager address
    /// @return The pool manager address
    function getPoolManager() external view returns (address);

    /// @notice Get the oracle address
    /// @return The oracle address
    function oracle() external view returns (address);

    /// @notice Get the vault address
    /// @return The vault address
    function vault() external view returns (address);

    /// @notice Get the executor address
    /// @return The executor address
    function executor() external view returns (address);

    /// @notice Check if the system is paused
    /// @return Whether the system is paused
    function paused() external view returns (bool);

    // ============ Events ============

    event OrderCreated(bytes32 indexed orderId, address indexed owner, TWAPTypes.OrderParams params);
    event OrderExecuted(bytes32 indexed orderId, uint32 chunkIndex, uint256 amountIn, uint256 amountOut);
    event OrderCompleted(bytes32 indexed orderId, uint256 totalAmountOut);
    event OrderCancelled(bytes32 indexed orderId, uint256 refundAmount);
    event ConfigUpdated(TWAPTypes.Config newConfig);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
}
