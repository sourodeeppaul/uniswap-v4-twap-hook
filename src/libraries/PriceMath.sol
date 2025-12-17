// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";

/// @title PriceMath
/// @notice Price calculation utilities for TWAP operations
library PriceMath {
    /// @notice Precision for price calculations (1e18)
    uint256 internal constant PRICE_PRECISION = 1e18;

    /// @notice Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum allowed deviation (99.99%)
    uint256 internal constant MAX_DEVIATION_BPS = 9999;

    error InvalidSqrtPrice();
    error DivisionByZero();
    error DeviationTooHigh();

    /// @notice Convert sqrtPriceX96 to a human-readable price
    /// @param sqrtPriceX96 The sqrt price in Q96 format
    /// @return price The price scaled by PRICE_PRECISION
    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96) internal pure returns (uint256 price) {
        if (sqrtPriceX96 == 0) revert InvalidSqrtPrice();

        // price = (sqrtPriceX96 / 2^96)^2 * PRICE_PRECISION
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        
        // Square the sqrt price
        uint256 priceX192 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1);
        
        // Convert from Q192 to price with precision
        price = FullMath.mulDiv(priceX192, PRICE_PRECISION, 1 << 192);
    }

    /// @notice Convert price to sqrtPriceX96
    /// @param price The price scaled by PRICE_PRECISION
    /// @return sqrtPriceX96 The sqrt price in Q96 format
    function priceToSqrtPriceX96(uint256 price) internal pure returns (uint160 sqrtPriceX96) {
        if (price == 0) revert InvalidSqrtPrice();

        // sqrtPriceX96 = sqrt(price * 2^192 / PRICE_PRECISION)
        uint256 priceX192 = FullMath.mulDiv(price, 1 << 192, PRICE_PRECISION);
        uint256 sqrtPrice = sqrt(priceX192);
        
        sqrtPriceX96 = uint160(sqrtPrice);
    }

    /// @notice Calculate TWAP from cumulative values
    /// @param tickCumulativeStart Starting cumulative tick
    /// @param tickCumulativeEnd Ending cumulative tick
    /// @param timeElapsed Time elapsed between observations
    /// @return twapTick The time-weighted average tick
    function calculateTWAPTick(
        int56 tickCumulativeStart,
        int56 tickCumulativeEnd,
        uint32 timeElapsed
    ) internal pure returns (int24 twapTick) {
        if (timeElapsed == 0) revert DivisionByZero();
        
        int56 tickCumulativeDelta = tickCumulativeEnd - tickCumulativeStart;
        twapTick = int24(tickCumulativeDelta / int56(uint56(timeElapsed)));
        
        // Round towards negative infinity
        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % int56(uint56(timeElapsed)) != 0)) {
            twapTick--;
        }
    }

    /// @notice Convert tick to price
    /// @param tick The tick value
    /// @return price The price scaled by PRICE_PRECISION
    function tickToPrice(int24 tick) internal pure returns (uint256 price) {
        // price = 1.0001^tick * PRICE_PRECISION
        uint256 absTick = tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick));
        
        uint256 ratio;
        
        if (absTick & 0x1 != 0) ratio = 0xfffcb933bd6fad37aa2d162d1a594001;
        else ratio = 0x100000000000000000000000000000000;
        
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // Convert to price precision
        price = FullMath.mulDiv(ratio, PRICE_PRECISION, 1 << 128);
    }

    /// @notice Calculate price deviation in basis points
    /// @param price1 First price
    /// @param price2 Second price
    /// @return deviationBps Deviation in basis points
    function calculateDeviationBps(uint256 price1, uint256 price2) internal pure returns (uint256 deviationBps) {
        if (price1 == 0 || price2 == 0) revert InvalidSqrtPrice();
        
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;
        
        deviationBps = FullMath.mulDiv(diff, BPS_DENOMINATOR, avg);
    }

    /// @notice Check if price deviation is within bounds
    /// @param currentPrice Current price
    /// @param referencePrice Reference price (e.g., TWAP)
    /// @param maxDeviationBps Maximum allowed deviation in bps
    /// @return isWithinBounds Whether deviation is acceptable
    function isDeviationWithinBounds(
        uint256 currentPrice,
        uint256 referencePrice,
        uint256 maxDeviationBps
    ) internal pure returns (bool isWithinBounds) {
        if (maxDeviationBps > MAX_DEVIATION_BPS) revert DeviationTooHigh();
        
        uint256 deviationBps = calculateDeviationBps(currentPrice, referencePrice);
        isWithinBounds = deviationBps <= maxDeviationBps;
    }

    /// @notice Calculate expected output amount given input
    /// @param amountIn Input amount
    /// @param price Price (scaled by PRICE_PRECISION)
    /// @param zeroForOne Direction (true = multiply, false = divide)
    /// @return amountOut Expected output amount
    function calculateOutput(
        uint256 amountIn,
        uint256 price,
        bool zeroForOne
    ) internal pure returns (uint256 amountOut) {
        if (price == 0) revert DivisionByZero();
        
        if (zeroForOne) {
            amountOut = FullMath.mulDiv(amountIn, price, PRICE_PRECISION);
        } else {
            amountOut = FullMath.mulDiv(amountIn, PRICE_PRECISION, price);
        }
    }

    /// @notice Calculate price impact in basis points
    /// @param inputAmount Amount being swapped
    /// @param poolLiquidity Total pool liquidity
    /// @return impactBps Estimated price impact in bps
    function estimatePriceImpact(
        uint256 inputAmount,
        uint256 poolLiquidity
    ) internal pure returns (uint256 impactBps) {
        if (poolLiquidity == 0) revert DivisionByZero();
        
        // Simplified impact: input / liquidity * 10000
        impactBps = FullMath.mulDiv(inputAmount, BPS_DENOMINATOR, poolLiquidity);
    }

    /// @notice Calculate weighted average price
    /// @param prices Array of prices
    /// @param weights Array of weights (must sum to PRICE_PRECISION)
    /// @return avgPrice Weighted average price
    function weightedAverage(
        uint256[] memory prices,
        uint256[] memory weights
    ) internal pure returns (uint256 avgPrice) {
        require(prices.length == weights.length, "Length mismatch");
        
        uint256 weightedSum = 0;
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < prices.length; i++) {
            weightedSum += prices[i] * weights[i];
            totalWeight += weights[i];
        }
        
        if (totalWeight == 0) revert DivisionByZero();
        avgPrice = weightedSum / totalWeight;
    }

    /// @notice Integer square root using Babylonian method
    /// @param x Value to take sqrt of
    /// @return y Square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
