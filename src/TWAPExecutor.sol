// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ITWAPExecutor} from "./interfaces/ITWAPExecutor.sol";
import {ITWAPOrderVault} from "./interfaces/ITWAPOrderVault.sol";
import {ITWAPOracle} from "./interfaces/ITWAPOracle.sol";
import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {TWAPTypes} from "./types/TWAPTypes.sol";
import {TWAPOrderLib} from "./libraries/TWAPOrderLib.sol";
import {ExecutionLib} from "./libraries/ExecutionLib.sol";
import {PriceMath} from "./libraries/PriceMath.sol";

/// @title TWAPExecutor
/// @notice Handles execution logic for TWAP orders
contract TWAPExecutor is ITWAPExecutor, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    // ============ State ============

    /// @notice Pool manager
    IPoolManager public immutable poolManager;

    /// @notice Order vault
    ITWAPOrderVault public vault;

    /// @notice Oracle
    ITWAPOracle public oracle;

    /// @notice Circuit breaker
    ICircuitBreaker public circuitBreaker;

    /// @notice Maximum gas per execution
    uint256 public maxGasPerExecution;

    /// @notice Keeper reward in basis points
    uint16 public keeperRewardBps;

    /// @notice Execution history per order
    mapping(bytes32 => TWAPTypes.ChunkExecution[]) public executionHistories;

    /// @notice Authorized hook address
    address public hook;

    // ============ Events ============

    // Inherited from ITWAPExecutor

    // ============ Modifiers ============

    modifier onlyHook() {
        require(msg.sender == hook, "Only hook");
        _;
    }

    modifier whenNotPaused() {
        require(!circuitBreaker.isTriggered(), "Circuit breaker active");
        _;
    }

    // ============ Constructor ============

    constructor(
        address _poolManager,
        address _vault,
        address _oracle,
        address _circuitBreaker,
        uint256 _maxGasPerExecution,
        uint16 _keeperRewardBps
    ) Ownable(msg.sender) {
        poolManager = IPoolManager(_poolManager);
        vault = ITWAPOrderVault(_vault);
        oracle = ITWAPOracle(_oracle);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        maxGasPerExecution = _maxGasPerExecution;
        keeperRewardBps = _keeperRewardBps;
    }

    // ============ Execution ============

    /// @inheritdoc ITWAPExecutor
    function executeChunk(bytes32 orderId)
        external
        override
        nonReentrant
        whenNotPaused
        returns (TWAPTypes.ExecutionResult result, uint256 amountOut)
    {
        uint256 gasStart = gasleft();
        
        // Get order from vault
        TWAPTypes.Order memory order = vault.getOrder(orderId);
        
        // Check if can execute
        (bool canExec, uint256 blocksUntil) = TWAPOrderLib.canExecute(order);
        if (!canExec) {
            if (TWAPOrderLib.isExpired(order)) {
                _handleExpiredOrder(order);
                return (TWAPTypes.ExecutionResult.Expired, 0);
            }
            if (blocksUntil > 0) {
                return (TWAPTypes.ExecutionResult.RateLimited, 0);
            }
            return (TWAPTypes.ExecutionResult.InsufficientLiquidity, 0);
        }
        
        // Calculate chunk amount
        uint256 chunkAmount = TWAPOrderLib.getNextChunkAmount(
            order.params.amountIn,
            order.params.numChunks,
            order.executionState.chunksExecuted
        );
        
        // Validate price
        (bool priceValid, , ) = oracle.validatePrice(order.params.poolKey, order.params.maxSlippageBps);
        if (!priceValid) {
            circuitBreaker.reportFailure(orderId);
            emit ExecutionFailed(orderId, TWAPTypes.ExecutionResult.PriceDeviation);
            return (TWAPTypes.ExecutionResult.PriceDeviation, 0);
        }
        
        // Execute the swap
        (result, amountOut) = _executeSwap(order, chunkAmount);
        
        if (result == TWAPTypes.ExecutionResult.Success) {
            // Record execution
            uint256 gasUsed = gasStart - gasleft();
            _recordExecution(order, chunkAmount, amountOut, gasUsed);
            
            // Update order state
            TWAPTypes.ExecutionState memory newState = TWAPOrderLib.updateExecutionState(
                order.executionState,
                chunkAmount,
                amountOut,
                gasUsed
            );
            
            TWAPTypes.OrderStatus newStatus = TWAPOrderLib.isComplete(order) 
                ? TWAPTypes.OrderStatus.Completed 
                : TWAPTypes.OrderStatus.Active;
            
            vault.updateOrder(orderId, newStatus, newState);
            
            // Pay keeper reward
            _payKeeperReward(order.params.poolKey, amountOut, msg.sender);
            
            circuitBreaker.reportSuccess(orderId);
            
            emit ChunkExecuted(
                orderId,
                order.executionState.chunksExecuted,
                chunkAmount,
                amountOut,
                gasUsed,
                msg.sender
            );
        } else {
            circuitBreaker.reportFailure(orderId);
            emit ExecutionFailed(orderId, result);
        }
    }

    /// @inheritdoc ITWAPExecutor
    function batchExecuteChunks(bytes32[] calldata orderIds)
        external
        override
        returns (TWAPTypes.ExecutionResult[] memory results, uint256[] memory amountsOut)
    {
        results = new TWAPTypes.ExecutionResult[](orderIds.length);
        amountsOut = new uint256[](orderIds.length);
        
        for (uint256 i = 0; i < orderIds.length; i++) {
            (results[i], amountsOut[i]) = this.executeChunk(orderIds[i]);
        }
    }

    /// @inheritdoc ITWAPExecutor
    function simulateExecution(bytes32 orderId)
        external
        view
        override
        returns (uint256 expectedOut, uint256 priceImpact)
    {
        TWAPTypes.Order memory order = vault.getOrder(orderId);
        
        uint256 chunkAmount = TWAPOrderLib.getNextChunkAmount(
            order.params.amountIn,
            order.params.numChunks,
            order.executionState.chunksExecuted
        );
        
        expectedOut = calculateExpectedOutput(
            order.params.poolKey,
            order.params.zeroForOne,
            chunkAmount
        );
        
        // Estimate price impact
        PoolId poolId = order.params.poolKey.toId();
        uint128 liquidity = poolManager.getLiquidity(poolId);
        priceImpact = PriceMath.estimatePriceImpact(chunkAmount, liquidity);
    }

    // ============ Execution Queries ============

    /// @inheritdoc ITWAPExecutor
    function canExecute(bytes32 orderId)
        external
        view
        override
        returns (bool canExec, uint256 blockUntilExecution)
    {
        TWAPTypes.Order memory order = vault.getOrder(orderId);
        return TWAPOrderLib.canExecute(order);
    }

    /// @inheritdoc ITWAPExecutor
    function getNextChunkAmount(bytes32 orderId) external view override returns (uint256 amount) {
        TWAPTypes.Order memory order = vault.getOrder(orderId);
        return TWAPOrderLib.getNextChunkAmount(
            order.params.amountIn,
            order.params.numChunks,
            order.executionState.chunksExecuted
        );
    }

    /// @inheritdoc ITWAPExecutor
    function getExecutionHistory(bytes32 orderId)
        external
        view
        override
        returns (TWAPTypes.ChunkExecution[] memory executions)
    {
        return executionHistories[orderId];
    }

    // ============ Price Calculations ============

    /// @inheritdoc ITWAPExecutor
    function calculateExpectedOutput(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn
    ) public view override returns (uint256 amountOut) {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        
        uint256 price = PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96);
        amountOut = PriceMath.calculateOutput(amountIn, price, zeroForOne);
    }

    /// @inheritdoc ITWAPExecutor
    function getCurrentPrice(PoolKey calldata poolKey) external view override returns (uint256 price) {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        price = PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96);
    }

    // ============ Configuration ============

    /// @inheritdoc ITWAPExecutor
    function setMaxGasPerExecution(uint256 maxGas) external override onlyOwner {
        maxGasPerExecution = maxGas;
        emit MaxGasUpdated(maxGas);
    }

    /// @inheritdoc ITWAPExecutor
    function setKeeperReward(uint16 rewardBps) external override onlyOwner {
        require(rewardBps <= 500, "Reward too high"); // Max 5%
        keeperRewardBps = rewardBps;
        emit KeeperRewardUpdated(rewardBps);
    }

    /// @inheritdoc ITWAPExecutor
    function getExecutorConfig() external view override returns (uint256 maxGas, uint16 rewardBps) {
        return (maxGasPerExecution, keeperRewardBps);
    }

    /// @notice Set the hook address
    function setHook(address _hook) external onlyOwner {
        hook = _hook;
    }

    /// @notice Update vault address
    function setVault(address _vault) external onlyOwner {
        vault = ITWAPOrderVault(_vault);
    }

    /// @notice Update oracle address
    function setOracle(address _oracle) external onlyOwner {
        oracle = ITWAPOracle(_oracle);
    }

    /// @notice Update circuit breaker address
    function setCircuitBreaker(address _circuitBreaker) external onlyOwner {
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // ============ Internal ============

    function _executeSwap(
        TWAPTypes.Order memory order,
        uint256 chunkAmount
    ) internal returns (TWAPTypes.ExecutionResult result, uint256 amountOut) {
        // Debit input from vault
        vault.debitInput(order.id, chunkAmount);
        
        // Get current price for limit calculation
        PoolId poolId = order.params.poolKey.toId();
        (uint160 currentSqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        
        // Calculate swap params
        (int256 amountSpecified, uint160 sqrtPriceLimitX96) = ExecutionLib.calculateSwapParams(
            chunkAmount,
            order.params.zeroForOne,
            order.params.maxSlippageBps,
            currentSqrtPriceX96
        );
        
        // Execute swap via pool manager
        // Note: In production, this would go through the hook's swap callback
        // For now, we simulate the expected output
        amountOut = calculateExpectedOutput(
            order.params.poolKey,
            order.params.zeroForOne,
            chunkAmount
        );
        
        // Credit output to vault
        (Currency inputCurrency, Currency outputCurrency) = ExecutionLib.getCurrencies(
            order.params.poolKey,
            order.params.zeroForOne
        );
        vault.creditOutput(order.id, outputCurrency, amountOut);
        
        // Validate output against minimum
        uint256 minChunkOutput = order.params.minAmountOut / order.params.numChunks;
        if (amountOut < minChunkOutput) {
            return (TWAPTypes.ExecutionResult.SlippageExceeded, 0);
        }
        
        return (TWAPTypes.ExecutionResult.Success, amountOut);
    }

    function _recordExecution(
        TWAPTypes.Order memory order,
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasUsed
    ) internal {
        TWAPTypes.ChunkExecution memory execution = TWAPTypes.ChunkExecution({
            orderId: order.id,
            chunkIndex: order.executionState.chunksExecuted,
            amountIn: amountIn,
            amountOut: amountOut,
            executionBlock: block.number,
            gasUsed: gasUsed
        });
        
        executionHistories[order.id].push(execution);
    }

    function _payKeeperReward(
        PoolKey memory poolKey,
        uint256 amountOut,
        address keeper
    ) internal {
        if (keeperRewardBps == 0) return;
        
        uint256 reward = ExecutionLib.calculateKeeperReward(amountOut, keeperRewardBps);
        if (reward > 0) {
            // Reward is paid from protocol fees or output
            // Implementation depends on fee structure
            emit KeeperRewarded(keeper, reward);
        }
    }

    function _handleExpiredOrder(TWAPTypes.Order memory order) internal {
        // Update status to expired
        vault.updateOrder(
            order.id,
            TWAPTypes.OrderStatus.Expired,
            order.executionState
        );
        
        // Refund remaining input to user
        if (order.executionState.amountInRemaining > 0) {
            vault.withdraw(
                order.id,
                order.params.zeroForOne ? order.params.poolKey.currency0 : order.params.poolKey.currency1,
                order.executionState.amountInRemaining,
                order.params.recipient
            );
        }
        
        // Transfer accumulated output to user
        if (order.executionState.amountOutAccumulated > 0) {
            vault.withdrawOutput(order.id, order.params.recipient);
        }
    }
}
