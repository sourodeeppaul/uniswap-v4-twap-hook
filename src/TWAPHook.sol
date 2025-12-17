// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITWAPHook} from "./interfaces/ITWAPHook.sol";
import {ITWAPOrderVault} from "./interfaces/ITWAPOrderVault.sol";
import {ITWAPExecutor} from "./interfaces/ITWAPExecutor.sol";
import {ITWAPOracle} from "./interfaces/ITWAPOracle.sol";
import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {TWAPTypes} from "./types/TWAPTypes.sol";
import {TWAPOrderLib} from "./libraries/TWAPOrderLib.sol";
import {CommitReveal} from "./security/CommitReveal.sol";
import {RateLimiter} from "./security/RateLimiter.sol";

/// @title TWAPHook
/// @notice Main Uniswap v4 Hook for TWAP order execution
/// @dev Implements time-weighted average price order splitting
contract TWAPHook is BaseHook, ITWAPHook, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    // ============ State ============

    /// @notice Order vault
    ITWAPOrderVault public twapVault;

    /// @notice Executor
    ITWAPExecutor public twapExecutor;

    /// @notice Oracle
    ITWAPOracle public twapOracle;

    /// @notice Circuit breaker
    ICircuitBreaker public circuitBreaker;

    /// @notice Commit-reveal for MEV protection
    CommitReveal public commitReveal;

    /// @notice Rate limiter
    RateLimiter public rateLimiter;

    /// @notice System configuration
    TWAPTypes.Config public config;

    /// @notice Order counter for ID generation
    uint256 public orderNonce;

    /// @notice Mapping of user to order IDs
    mapping(address => bytes32[]) private userOrderIds;

    /// @notice Whether the system is paused
    bool private _paused;

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _vault,
        address _executor,
        address _oracle,
        address _circuitBreaker,
        address _commitReveal,
        address _rateLimiter
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        twapVault = ITWAPOrderVault(_vault);
        twapExecutor = ITWAPExecutor(_executor);
        twapOracle = ITWAPOracle(_oracle);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        commitReveal = CommitReveal(_commitReveal);
        rateLimiter = RateLimiter(_rateLimiter);

        // Default configuration
        config = TWAPTypes.Config({
            minChunkSize: 1e15, // 0.001 tokens
            maxChunkSize: 1e24, // 1M tokens
            minIntervalBlocks: 1,
            maxIntervalBlocks: 1000,
            maxOrderDuration: 50000, // ~1 week in blocks
            commitRevealDelay: 2,
            maxSlippageBps: 500, // 5%
            protocolFeeBps: 10 // 0.1%
        });
    }

    // ============ Hook Configuration ============

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Hook Callbacks ============

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Check circuit breaker
        if (circuitBreaker.isTriggered()) {
            revert TWAPTypes.CircuitBreakerActive();
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // After each swap, check if there are TWAP orders ready to execute
        // This is a simplified approach - in production, use keeper-triggered execution
        _tryExecutePendingOrders(key);

        return (this.afterSwap.selector, 0);
    }

    // ============ Order Management ============

    /// @inheritdoc ITWAPHook
    function createOrder(TWAPTypes.OrderParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (bytes32 orderId)
    {
        // Check if paused
        require(!_paused, "Paused");

        // Validate parameters
        TWAPOrderLib.validateOrderParams(params, config);

        // Check rate limit
        rateLimiter.checkAndUpdate(msg.sender, params.amountIn);

        // Generate order ID
        orderNonce++;
        orderId = TWAPOrderLib.generateOrderId(msg.sender, params.poolKey, orderNonce);

        // Create order
        TWAPTypes.Order memory order = TWAPTypes.Order({
            id: orderId,
            owner: msg.sender,
            params: params,
            status: TWAPTypes.OrderStatus.Pending,
            executionState: TWAPOrderLib.createInitialState(params.amountIn),
            createdAt: block.number,
            updatedAt: block.number
        });

        // Determine input currency
        Currency inputCurrency = params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1;

        // Transfer tokens to twapVault
        if (!inputCurrency.isAddressZero()) {
            IERC20(Currency.unwrap(inputCurrency)).safeTransferFrom(msg.sender, address(twapVault), params.amountIn);
        }

        // Store order in twapVault
        twapVault.storeOrder(order);
        twapVault.deposit(orderId, inputCurrency, params.amountIn, msg.sender);

        // Track user's orders
        userOrderIds[msg.sender].push(orderId);

        emit OrderCreated(orderId, msg.sender, params);

        return orderId;
    }

    /// @inheritdoc ITWAPHook
    function cancelOrder(bytes32 orderId) external override nonReentrant {
        TWAPTypes.Order memory order = twapVault.getOrder(orderId);

        // Verify ownership
        require(order.owner == msg.sender, "Not owner");

        // Verify cancellable status
        require(
            order.status == TWAPTypes.OrderStatus.Pending || order.status == TWAPTypes.OrderStatus.Active,
            "Cannot cancel"
        );

        // Calculate refund
        uint256 refundAmount = order.executionState.amountInRemaining;
        Currency inputCurrency =
            order.params.zeroForOne ? order.params.poolKey.currency0 : order.params.poolKey.currency1;

        // Update order status
        twapVault.updateOrder(orderId, TWAPTypes.OrderStatus.Cancelled, order.executionState);

        // Refund remaining input
        if (refundAmount > 0) {
            twapVault.withdraw(orderId, inputCurrency, refundAmount, msg.sender);
        }

        // Withdraw accumulated output
        uint256 outputAmount = twapVault.getOutputBalance(orderId);
        if (outputAmount > 0) {
            twapVault.withdrawOutput(orderId, msg.sender);
        }

        emit OrderCancelled(orderId, refundAmount);
    }

    /// @inheritdoc ITWAPHook
    function getOrder(bytes32 orderId) external view override returns (TWAPTypes.Order memory order) {
        return twapVault.getOrder(orderId);
    }

    /// @inheritdoc ITWAPHook
    function getUserOrders(address user) external view override returns (bytes32[] memory orderIds) {
        return userOrderIds[user];
    }

    /// @inheritdoc ITWAPHook
    function canExecuteOrder(bytes32 orderId)
        external
        view
        override
        returns (bool canExecute, string memory reason)
    {
        TWAPTypes.Order memory order = twapVault.getOrder(orderId);

        if (order.status != TWAPTypes.OrderStatus.Active && order.status != TWAPTypes.OrderStatus.Pending) {
            return (false, "Invalid status");
        }

        if (block.timestamp > order.params.deadline) {
            return (false, "Order expired");
        }

        if (order.executionState.chunksExecuted >= order.params.numChunks) {
            return (false, "All chunks executed");
        }

        uint256 nextExecutionBlock = order.executionState.lastExecutionBlock + order.params.intervalBlocks;
        if (block.number < nextExecutionBlock) {
            return (false, "Too early");
        }

        if (circuitBreaker.isTriggered()) {
            return (false, "Circuit breaker active");
        }

        return (true, "");
    }

    // ============ Execution ============

    /// @inheritdoc ITWAPHook
    function executeOrder(bytes32 orderId)
        external
        override
        nonReentrant
        returns (TWAPTypes.ExecutionResult result)
    {
        require(!_paused, "Paused");
        require(!circuitBreaker.isTriggered(), "Circuit breaker active");

        (result,) = twapExecutor.executeChunk(orderId);

        // Check if order completed
        TWAPTypes.Order memory order = twapVault.getOrder(orderId);
        if (order.executionState.chunksExecuted >= order.params.numChunks) {
            // Withdraw all output to recipient
            twapVault.withdrawOutput(orderId, order.params.recipient);
            emit OrderCompleted(orderId, order.executionState.amountOutAccumulated);
        } else {
            emit OrderExecuted(
                orderId,
                order.executionState.chunksExecuted,
                TWAPOrderLib.calculateChunkAmount(order.params.amountIn, order.params.numChunks),
                order.executionState.amountOutAccumulated
            );
        }
    }

    /// @inheritdoc ITWAPHook
    function batchExecuteOrders(bytes32[] calldata orderIds)
        external
        override
        returns (TWAPTypes.ExecutionResult[] memory results)
    {
        require(!_paused, "Paused");

        results = new TWAPTypes.ExecutionResult[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            try this.executeOrder(orderIds[i]) returns (TWAPTypes.ExecutionResult result) {
                results[i] = result;
            } catch {
                results[i] = TWAPTypes.ExecutionResult.InsufficientLiquidity;
            }
        }
    }

    /// @inheritdoc ITWAPHook
    function getExecutableOrders(uint256 maxOrders)
        external
        view
        override
        returns (bytes32[] memory orderIds)
    {
        bytes32[] memory activeOrders = twapVault.getOrdersByStatus(TWAPTypes.OrderStatus.Active, 0, 1000);

        bytes32[] memory temp = new bytes32[](maxOrders);
        uint256 count = 0;

        for (uint256 i = 0; i < activeOrders.length && count < maxOrders; i++) {
            (bool canExec,) = twapExecutor.canExecute(activeOrders[i]);
            if (canExec) {
                temp[count] = activeOrders[i];
                count++;
            }
        }

        // Resize array
        orderIds = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = temp[i];
        }
    }

    // ============ Configuration ============

    /// @inheritdoc ITWAPHook
    function getConfig() external view override returns (TWAPTypes.Config memory) {
        return config;
    }

    /// @inheritdoc ITWAPHook
    function updateConfig(TWAPTypes.Config calldata newConfig) external override onlyOwner {
        config = newConfig;
        emit ConfigUpdated(newConfig);
    }

    // ============ View Functions ============

    /// @inheritdoc ITWAPHook
    function getPoolManager() external view override returns (address) {
        return address(poolManager);
    }

    /// @inheritdoc ITWAPHook
    function oracle() external view override returns (address) {
        return address(twapOracle);
    }

    /// @inheritdoc ITWAPHook
    function vault() external view override returns (address) {
        return address(twapVault);
    }

    /// @inheritdoc ITWAPHook
    function executor() external view override returns (address) {
        return address(twapExecutor);
    }

    /// @inheritdoc ITWAPHook
    function paused() external view override returns (bool) {
        return _paused;
    }

    // ============ Admin Functions ============

    /// @notice Pause the system
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the system
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Update component addresses
    function setComponents(
        address _vault,
        address _executor,
        address _oracle,
        address _circuitBreaker
    ) external onlyOwner {
        if (_vault != address(0)) twapVault = ITWAPOrderVault(_vault);
        if (_executor != address(0)) twapExecutor = ITWAPExecutor(_executor);
        if (_oracle != address(0)) twapOracle = ITWAPOracle(_oracle);
        if (_circuitBreaker != address(0)) circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // ============ Internal ============

    function _tryExecutePendingOrders(PoolKey calldata key) internal {
        // This is called after each swap to opportunistically execute pending orders
        // In production, this should be rate-limited or handled by keepers
        bytes32[] memory executableOrders = this.getExecutableOrders(5);

        for (uint256 i = 0; i < executableOrders.length; i++) {
            try this.executeOrder(executableOrders[i]) {} catch {}
        }
    }
}
