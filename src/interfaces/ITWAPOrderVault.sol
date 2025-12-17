// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "v4-core/types/Currency.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title ITWAPOrderVault
/// @notice Interface for the TWAP Order Vault - manages token custody and order storage
interface ITWAPOrderVault {
    // ============ Deposit/Withdrawal ============

    /// @notice Deposit tokens for a new order
    /// @param orderId The order ID
    /// @param currency The token to deposit
    /// @param amount Amount to deposit
    /// @param owner The order owner
    function deposit(bytes32 orderId, Currency currency, uint256 amount, address owner) external;

    /// @notice Withdraw tokens after order completion or cancellation
    /// @param orderId The order ID
    /// @param currency The token to withdraw
    /// @param amount Amount to withdraw
    /// @param recipient Recipient of the tokens
    function withdraw(bytes32 orderId, Currency currency, uint256 amount, address recipient) external;

    /// @notice Withdraw accumulated output tokens to recipient
    /// @param orderId The order ID
    /// @param recipient Recipient of the tokens
    /// @return amount Amount withdrawn
    function withdrawOutput(bytes32 orderId, address recipient) external returns (uint256 amount);

    /// @notice Debit input tokens during execution
    /// @param orderId The order ID
    /// @param amount Amount to debit
    function debitInput(bytes32 orderId, uint256 amount) external;

    /// @notice Credit output tokens during execution
    /// @param orderId The order ID
    /// @param currency The output currency
    /// @param amount Amount to credit
    function creditOutput(bytes32 orderId, Currency currency, uint256 amount) external;

    // ============ Order Storage ============

    /// @notice Store a new order
    /// @param order The order to store
    function storeOrder(TWAPTypes.Order calldata order) external;

    /// @notice Update order state
    /// @param orderId The order ID
    /// @param status New status
    /// @param executionState Updated execution state
    function updateOrder(
        bytes32 orderId,
        TWAPTypes.OrderStatus status,
        TWAPTypes.ExecutionState calldata executionState
    ) external;

    /// @notice Get order by ID
    /// @param orderId The order ID
    /// @return order The order details
    function getOrder(bytes32 orderId) external view returns (TWAPTypes.Order memory order);

    /// @notice Check if order exists
    /// @param orderId The order ID
    /// @return exists Whether the order exists
    function orderExists(bytes32 orderId) external view returns (bool exists);

    // ============ Balance Queries ============

    /// @notice Get input token balance for an order
    /// @param orderId The order ID
    /// @return balance The input token balance
    function getInputBalance(bytes32 orderId) external view returns (uint256 balance);

    /// @notice Get output token balance for an order
    /// @param orderId The order ID
    /// @return balance The output token balance
    function getOutputBalance(bytes32 orderId) external view returns (uint256 balance);

    /// @notice Get total deposits for a currency
    /// @param currency The currency
    /// @return total Total deposited amount
    function getTotalDeposits(Currency currency) external view returns (uint256 total);

    // ============ Order Queries ============

    /// @notice Get all order IDs for a user
    /// @param user The user address
    /// @return orderIds Array of order IDs
    function getUserOrderIds(address user) external view returns (bytes32[] memory orderIds);

    /// @notice Get active orders count
    /// @return count Number of active orders
    function getActiveOrderCount() external view returns (uint256 count);

    /// @notice Get orders by status
    /// @param status The status to filter by
    /// @param offset Pagination offset
    /// @param limit Maximum results
    /// @return orderIds Array of matching order IDs
    function getOrdersByStatus(TWAPTypes.OrderStatus status, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory orderIds);

    // ============ Access Control ============

    /// @notice Set the authorized hook address
    /// @param hook The hook address
    function setHook(address hook) external;

    /// @notice Set the authorized executor address
    /// @param executor The executor address
    function setExecutor(address executor) external;

    // ============ Events ============

    event Deposited(bytes32 indexed orderId, Currency indexed currency, uint256 amount);
    event Withdrawn(bytes32 indexed orderId, Currency indexed currency, uint256 amount, address recipient);
    event OrderStored(bytes32 indexed orderId, address indexed owner);
    event OrderUpdated(bytes32 indexed orderId, TWAPTypes.OrderStatus status);
    event HookSet(address indexed hook);
    event ExecutorSet(address indexed executor);
}
