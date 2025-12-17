// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";
import {PriceMath} from "./PriceMath.sol";

/// @title ExecutionLib
/// @notice Library for trade execution calculations and delta handling
library ExecutionLib {
    /// @notice Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Protocol fee cap
    uint256 internal constant MAX_PROTOCOL_FEE_BPS = 100; // 1%

    error InsufficientOutput();
    error NegativeDelta();
    error FeeTooHigh();

    /// @notice Calculate swap parameters for a chunk
    /// @param amountIn Input amount for the chunk
    /// @param zeroForOne Swap direction
    /// @param maxSlippageBps Maximum allowed slippage
    /// @param currentSqrtPriceX96 Current pool sqrt price
    /// @return amountSpecified Amount to specify in swap (negative for exact input)
    /// @return sqrtPriceLimitX96 Price limit for slippage protection
    function calculateSwapParams(
        uint256 amountIn,
        bool zeroForOne,
        uint16 maxSlippageBps,
        uint160 currentSqrtPriceX96
    ) internal pure returns (int256 amountSpecified, uint160 sqrtPriceLimitX96) {
        // Exact input swap (negative amount)
        amountSpecified = -int256(amountIn);
        
        // Calculate price limit based on slippage tolerance
        sqrtPriceLimitX96 = calculatePriceLimit(currentSqrtPriceX96, zeroForOne, maxSlippageBps);
    }

    /// @notice Calculate price limit for slippage protection
    /// @param currentSqrtPriceX96 Current sqrt price
    /// @param zeroForOne Swap direction
    /// @param slippageBps Slippage tolerance in bps
    /// @return sqrtPriceLimitX96 Price limit
    function calculatePriceLimit(
        uint160 currentSqrtPriceX96,
        bool zeroForOne,
        uint16 slippageBps
    ) internal pure returns (uint160 sqrtPriceLimitX96) {
        // For zeroForOne, price goes down, so limit is lower
        // For oneForZero, price goes up, so limit is higher
        uint256 slippageFactor = zeroForOne 
            ? BPS_DENOMINATOR - slippageBps 
            : BPS_DENOMINATOR + slippageBps;
        
        // Apply to sqrt price (half the slippage since we're dealing with sqrt)
        uint256 sqrtSlippageFactor = PriceMath.sqrt(slippageFactor * 1e18) * 1e9 / 1e18;
        
        sqrtPriceLimitX96 = uint160(
            FullMath.mulDiv(currentSqrtPriceX96, sqrtSlippageFactor, 1e9)
        );
        
        // Ensure valid bounds
        if (zeroForOne) {
            // Minimum sqrt price (TickMath.MIN_SQRT_PRICE)
            uint160 minPrice = 4295128739;
            if (sqrtPriceLimitX96 < minPrice) sqrtPriceLimitX96 = minPrice;
        } else {
            // Maximum sqrt price (TickMath.MAX_SQRT_PRICE)
            uint160 maxPrice = 1461446703485210103287273052203988822378723970342;
            if (sqrtPriceLimitX96 > maxPrice) sqrtPriceLimitX96 = maxPrice;
        }
    }

    /// @notice Extract amounts from balance delta
    /// @param delta The balance delta from swap
    /// @param zeroForOne Swap direction
    /// @return amountIn Actual amount of input used
    /// @return amountOut Actual amount of output received
    function extractAmounts(
        BalanceDelta delta,
        bool zeroForOne
    ) internal pure returns (uint256 amountIn, uint256 amountOut) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        
        if (zeroForOne) {
            // token0 -> token1: amount0 is negative (spent), amount1 is positive (received)
            if (amount0 > 0) revert NegativeDelta();
            amountIn = uint256(uint128(-amount0));
            amountOut = amount1 > 0 ? uint256(uint128(amount1)) : 0;
        } else {
            // token1 -> token0: amount1 is negative (spent), amount0 is positive (received)
            if (amount1 > 0) revert NegativeDelta();
            amountIn = uint256(uint128(-amount1));
            amountOut = amount0 > 0 ? uint256(uint128(amount0)) : 0;
        }
    }

    /// @notice Validate output meets minimum requirements
    /// @param actualOutput Actual output received
    /// @param expectedOutput Expected output based on price
    /// @param minSlippageBps Minimum acceptable slippage
    function validateOutput(
        uint256 actualOutput,
        uint256 expectedOutput,
        uint16 minSlippageBps
    ) internal pure {
        uint256 minOutput = FullMath.mulDiv(
            expectedOutput, 
            BPS_DENOMINATOR - minSlippageBps, 
            BPS_DENOMINATOR
        );
        
        if (actualOutput < minOutput) {
            revert InsufficientOutput();
        }
    }

    /// @notice Calculate keeper reward
    /// @param amountOut Output amount
    /// @param rewardBps Reward percentage in bps
    /// @return reward Keeper reward amount
    function calculateKeeperReward(
        uint256 amountOut,
        uint16 rewardBps
    ) internal pure returns (uint256 reward) {
        reward = FullMath.mulDiv(amountOut, rewardBps, BPS_DENOMINATOR);
    }

    /// @notice Calculate protocol fee
    /// @param amount Amount to take fee from
    /// @param feeBps Fee in basis points
    /// @return fee Protocol fee amount
    function calculateProtocolFee(
        uint256 amount,
        uint16 feeBps
    ) internal pure returns (uint256 fee) {
        if (feeBps > MAX_PROTOCOL_FEE_BPS) revert FeeTooHigh();
        fee = FullMath.mulDiv(amount, feeBps, BPS_DENOMINATOR);
    }

    /// @notice Determine input and output currencies
    /// @param poolKey The pool key
    /// @param zeroForOne Swap direction
    /// @return inputCurrency Currency being sold
    /// @return outputCurrency Currency being bought
    function getCurrencies(
        PoolKey memory poolKey,
        bool zeroForOne
    ) internal pure returns (Currency inputCurrency, Currency outputCurrency) {
        if (zeroForOne) {
            inputCurrency = poolKey.currency0;
            outputCurrency = poolKey.currency1;
        } else {
            inputCurrency = poolKey.currency1;
            outputCurrency = poolKey.currency0;
        }
    }

    /// @notice Calculate effective price from execution
    /// @param amountIn Input amount
    /// @param amountOut Output amount
    /// @return price Effective price (scaled by 1e18)
    function calculateEffectivePrice(
        uint256 amountIn,
        uint256 amountOut
    ) internal pure returns (uint256 price) {
        if (amountIn == 0) return 0;
        price = FullMath.mulDiv(amountOut, PriceMath.PRICE_PRECISION, amountIn);
    }

    /// @notice Calculate execution report
    /// @param order The executed order
    /// @param chunkAmountIn Amount input for this chunk
    /// @param chunkAmountOut Amount output for this chunk
    /// @return report Formatted execution report
    function createExecutionReport(
        TWAPTypes.Order memory order,
        uint256 chunkAmountIn,
        uint256 chunkAmountOut
    ) internal view returns (TWAPTypes.ChunkExecution memory report) {
        report.orderId = order.id;
        report.chunkIndex = order.executionState.chunksExecuted;
        report.amountIn = chunkAmountIn;
        report.amountOut = chunkAmountOut;
        report.executionBlock = block.number;
        report.gasUsed = 0; // Set by caller
    }

    /// @notice Check if execution improves average price
    /// @param currentAvgPrice Current average execution price
    /// @param newPrice New execution price
    /// @param zeroForOne Swap direction
    /// @return isImproved Whether price improved
    function isPriceImproved(
        uint256 currentAvgPrice,
        uint256 newPrice,
        bool zeroForOne
    ) internal pure returns (bool isImproved) {
        if (currentAvgPrice == 0) return true;
        
        // For zeroForOne: higher output per input is better
        // For oneForZero: lower input per output is better
        isImproved = zeroForOne ? newPrice >= currentAvgPrice : newPrice <= currentAvgPrice;
    }
}
