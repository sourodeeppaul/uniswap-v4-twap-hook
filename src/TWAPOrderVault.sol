// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ITWAPOrderVault} from "./interfaces/ITWAPOrderVault.sol";
import {TWAPTypes} from "./types/TWAPTypes.sol";

/// @title TWAPOrderVault
/// @notice Manages token custody and order storage for TWAP orders
contract TWAPOrderVault is ITWAPOrderVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using CurrencyLibrary for Currency;

    // ============ State ============

    /// @notice Authorized hook address
    address public hook;

    /// @notice Authorized executor address
    address public executor;

    /// @notice Mapping of order ID to Order
    mapping(bytes32 => TWAPTypes.Order) public orders;

    /// @notice Mapping of order ID to input token balance
    mapping(bytes32 => uint256) public inputBalances;

    /// @notice Mapping of order ID to output token balance
    mapping(bytes32 => uint256) public outputBalances;

    /// @notice Mapping of currency to total deposits
    mapping(Currency => uint256) public totalDeposits;

    /// @notice Mapping of user to their order IDs
    mapping(address => EnumerableSet.Bytes32Set) private userOrders;

    /// @notice Set of all active order IDs
    EnumerableSet.Bytes32Set private activeOrders;

    /// @notice Mapping of order ID to input currency
    mapping(bytes32 => Currency) public orderInputCurrency;

    /// @notice Mapping of order ID to output currency
    mapping(bytes32 => Currency) public orderOutputCurrency;

    // ============ Modifiers ============

    modifier onlyHook() {
        require(msg.sender == hook, "Only hook");
        _;
    }

    modifier onlyHookOrExecutor() {
        require(msg.sender == hook || msg.sender == executor, "Not authorized");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Deposit/Withdrawal ============

    /// @inheritdoc ITWAPOrderVault
    function deposit(
        bytes32 orderId,
        Currency currency,
        uint256 amount,
        address owner
    ) external override onlyHook nonReentrant {
        require(amount > 0, "Zero amount");
        
        // Transfer tokens from owner
        if (!currency.isAddressZero()) {
            IERC20(Currency.unwrap(currency)).safeTransferFrom(owner, address(this), amount);
        }
        
        inputBalances[orderId] += amount;
        totalDeposits[currency] += amount;
        orderInputCurrency[orderId] = currency;
        
        emit Deposited(orderId, currency, amount);
    }

    /// @inheritdoc ITWAPOrderVault
    function withdraw(
        bytes32 orderId,
        Currency currency,
        uint256 amount,
        address recipient
    ) external override onlyHookOrExecutor nonReentrant {
        require(amount > 0, "Zero amount");
        require(recipient != address(0), "Invalid recipient");
        
        // Determine if withdrawing input or output
        if (Currency.unwrap(currency) == Currency.unwrap(orderInputCurrency[orderId])) {
            require(inputBalances[orderId] >= amount, "Insufficient balance");
            inputBalances[orderId] -= amount;
        } else {
            require(outputBalances[orderId] >= amount, "Insufficient balance");
            outputBalances[orderId] -= amount;
        }
        
        totalDeposits[currency] -= amount;
        
        // Transfer tokens
        if (currency.isAddressZero()) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(Currency.unwrap(currency)).safeTransfer(recipient, amount);
        }
        
        emit Withdrawn(orderId, currency, amount, recipient);
    }

    /// @inheritdoc ITWAPOrderVault
    function withdrawOutput(bytes32 orderId, address recipient) external override onlyHookOrExecutor nonReentrant returns (uint256 amount) {
        amount = outputBalances[orderId];
        require(amount > 0, "No output to withdraw");
        
        Currency currency = orderOutputCurrency[orderId];
        outputBalances[orderId] = 0;
        totalDeposits[currency] -= amount;
        
        if (currency.isAddressZero()) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(Currency.unwrap(currency)).safeTransfer(recipient, amount);
        }
        
        emit Withdrawn(orderId, currency, amount, recipient);
    }

    /// @notice Credit output tokens to an order (called by executor after swap)
    /// @param orderId The order ID
    /// @param currency The output currency
    /// @param amount Amount to credit
    function creditOutput(bytes32 orderId, Currency currency, uint256 amount) external onlyHookOrExecutor {
        outputBalances[orderId] += amount;
        totalDeposits[currency] += amount;
        orderOutputCurrency[orderId] = currency;
    }

    /// @notice Debit input tokens from an order (called by executor before swap)
    /// @param orderId The order ID
    /// @param amount Amount to debit
    function debitInput(bytes32 orderId, uint256 amount) external onlyHookOrExecutor {
        require(inputBalances[orderId] >= amount, "Insufficient input");
        inputBalances[orderId] -= amount;
        totalDeposits[orderInputCurrency[orderId]] -= amount;
    }

    // ============ Order Storage ============

    /// @inheritdoc ITWAPOrderVault
    function storeOrder(TWAPTypes.Order calldata order) external override onlyHook {
        require(orders[order.id].id == bytes32(0), "Order exists");
        
        orders[order.id] = order;
        userOrders[order.owner].add(order.id);
        activeOrders.add(order.id);
        
        emit OrderStored(order.id, order.owner);
    }

    /// @inheritdoc ITWAPOrderVault
    function updateOrder(
        bytes32 orderId,
        TWAPTypes.OrderStatus status,
        TWAPTypes.ExecutionState calldata executionState
    ) external override onlyHookOrExecutor {
        require(orders[orderId].id != bytes32(0), "Order not found");
        
        orders[orderId].status = status;
        orders[orderId].executionState = executionState;
        orders[orderId].updatedAt = block.number;
        
        // Remove from active if completed/cancelled/expired
        if (status == TWAPTypes.OrderStatus.Completed ||
            status == TWAPTypes.OrderStatus.Cancelled ||
            status == TWAPTypes.OrderStatus.Expired ||
            status == TWAPTypes.OrderStatus.Failed) {
            activeOrders.remove(orderId);
        }
        
        emit OrderUpdated(orderId, status);
    }

    /// @inheritdoc ITWAPOrderVault
    function getOrder(bytes32 orderId) external view override returns (TWAPTypes.Order memory order) {
        order = orders[orderId];
        require(order.id != bytes32(0), "Order not found");
    }

    /// @inheritdoc ITWAPOrderVault
    function orderExists(bytes32 orderId) external view override returns (bool exists) {
        return orders[orderId].id != bytes32(0);
    }

    // ============ Balance Queries ============

    /// @inheritdoc ITWAPOrderVault
    function getInputBalance(bytes32 orderId) external view override returns (uint256 balance) {
        return inputBalances[orderId];
    }

    /// @inheritdoc ITWAPOrderVault
    function getOutputBalance(bytes32 orderId) external view override returns (uint256 balance) {
        return outputBalances[orderId];
    }

    /// @inheritdoc ITWAPOrderVault
    function getTotalDeposits(Currency currency) external view override returns (uint256 total) {
        return totalDeposits[currency];
    }

    // ============ Order Queries ============

    /// @inheritdoc ITWAPOrderVault
    function getUserOrderIds(address user) external view override returns (bytes32[] memory orderIds) {
        return userOrders[user].values();
    }

    /// @inheritdoc ITWAPOrderVault
    function getActiveOrderCount() external view override returns (uint256 count) {
        return activeOrders.length();
    }

    /// @inheritdoc ITWAPOrderVault
    function getOrdersByStatus(
        TWAPTypes.OrderStatus status,
        uint256 offset,
        uint256 limit
    ) external view override returns (bytes32[] memory orderIds) {
        uint256 count = 0;
        bytes32[] memory temp = new bytes32[](activeOrders.length());
        
        for (uint256 i = 0; i < activeOrders.length() && count < limit; i++) {
            bytes32 orderId = activeOrders.at(i);
            if (orders[orderId].status == status) {
                if (count >= offset) {
                    temp[count - offset] = orderId;
                }
                count++;
            }
        }
        
        // Resize array
        orderIds = new bytes32[](count > offset ? count - offset : 0);
        for (uint256 i = 0; i < orderIds.length; i++) {
            orderIds[i] = temp[i];
        }
    }

    /// @notice Get all active order IDs
    /// @return orderIds Array of active order IDs
    function getActiveOrderIds() external view returns (bytes32[] memory orderIds) {
        return activeOrders.values();
    }

    // ============ Access Control ============

    /// @inheritdoc ITWAPOrderVault
    function setHook(address _hook) external override onlyOwner {
        require(_hook != address(0), "Invalid hook");
        hook = _hook;
        emit HookSet(_hook);
    }

    /// @inheritdoc ITWAPOrderVault
    function setExecutor(address _executor) external override onlyOwner {
        require(_executor != address(0), "Invalid executor");
        executor = _executor;
        emit ExecutorSet(_executor);
    }

    // ============ ETH Handling ============

    receive() external payable {}
}
