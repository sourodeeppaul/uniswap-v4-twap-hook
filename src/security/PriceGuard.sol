// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {ITWAPOracle} from "../interfaces/ITWAPOracle.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

/// @title PriceGuard
/// @notice Protection against price manipulation attacks
/// @dev Validates execution prices against TWAP and detects manipulation
contract PriceGuard is Ownable {
    using PoolIdLibrary for PoolKey;

    // ============ State ============

    /// @notice Oracle for price data
    ITWAPOracle public oracle;

    /// @notice Maximum allowed deviation from TWAP in bps
    uint16 public maxDeviationBps;

    /// @notice Minimum TWAP window for validation (blocks)
    uint32 public minTWAPWindow;

    /// @notice Number of blocks to look back for manipulation detection
    uint32 public lookbackBlocks;

    /// @notice History of price observations per pool
    mapping(bytes32 => PriceHistory) public priceHistories;

    /// @notice Blocked pools (detected manipulation)
    mapping(bytes32 => BlockedPool) public blockedPools;

    // ============ Structs ============

    struct PriceHistory {
        uint256[] prices;
        uint256[] timestamps;
        uint256 head; // Circular buffer head
        uint256 size; // Current size
    }

    struct BlockedPool {
        bool isBlocked;
        uint256 blockedAt;
        string reason;
    }

    // ============ Events ============

    event PriceValidated(bytes32 indexed poolId, uint256 spotPrice, uint256 twapPrice, uint256 deviationBps);
    event ManipulationDetected(bytes32 indexed poolId, uint256 currentPrice, uint256 expectedPrice, string reason);
    event PoolBlocked(bytes32 indexed poolId, string reason);
    event PoolUnblocked(bytes32 indexed poolId);
    event OracleUpdated(address indexed newOracle);
    event MaxDeviationUpdated(uint16 newMaxDeviationBps);
    event TWAPWindowUpdated(uint32 newMinWindow);

    // ============ Errors ============

    error PriceDeviationTooHigh(uint256 spotPrice, uint256 twapPrice, uint256 deviationBps);
    error PoolIsBlocked(bytes32 poolId);
    error ManipulationError();
    error OracleNotSet();
    error InsufficientPriceHistory();
    error InvalidConfiguration();

    // ============ Constructor ============

    constructor(
        address _oracle,
        uint16 _maxDeviationBps,
        uint32 _minTWAPWindow,
        uint32 _lookbackBlocks
    ) Ownable(msg.sender) {
        if (_maxDeviationBps == 0 || _maxDeviationBps > 5000) revert InvalidConfiguration();
        if (_minTWAPWindow == 0) revert InvalidConfiguration();
        
        oracle = ITWAPOracle(_oracle);
        maxDeviationBps = _maxDeviationBps;
        minTWAPWindow = _minTWAPWindow;
        lookbackBlocks = _lookbackBlocks;
    }

    // ============ Price Validation ============

    /// @notice Validate current price before execution
    /// @param poolKey The pool to validate
    /// @return isValid Whether price is within acceptable bounds
    function validatePrice(PoolKey calldata poolKey) external view returns (bool isValid) {
        if (address(oracle) == address(0)) revert OracleNotSet();
        
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        
        // Check if pool is blocked
        if (blockedPools[poolId].isBlocked) {
            revert PoolIsBlocked(poolId);
        }
        
        // Get spot and TWAP prices
        (bool priceValid, uint256 spotPrice, uint256 twapPrice) = 
            oracle.validatePrice(poolKey, maxDeviationBps);
        
        if (!priceValid) {
            uint256 deviationBps = PriceMath.calculateDeviationBps(spotPrice, twapPrice);
            revert PriceDeviationTooHigh(spotPrice, twapPrice, deviationBps);
        }
        
        return true;
    }

    /// @notice Full price check with manipulation detection
    /// @param poolKey The pool to check
    /// @return isValid Whether price is valid
    /// @return spotPrice Current spot price
    /// @return twapPrice TWAP price
    /// @return deviationBps Price deviation in bps
    function fullPriceCheck(PoolKey calldata poolKey)
        external
        view
        returns (
            bool isValid,
            uint256 spotPrice,
            uint256 twapPrice,
            uint256 deviationBps
        )
    {
        if (address(oracle) == address(0)) revert OracleNotSet();
        
        // Get prices
        (isValid, spotPrice, twapPrice) = oracle.validatePrice(poolKey, maxDeviationBps);
        
        // Calculate deviation
        deviationBps = PriceMath.calculateDeviationBps(spotPrice, twapPrice);
    }

    /// @notice Record price observation for manipulation detection
    /// @param poolKey The pool
    /// @param price The observed price
    function recordPriceObservation(PoolKey calldata poolKey, uint256 price) external {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        PriceHistory storage history = priceHistories[poolId];
        
        // Initialize if needed
        if (history.prices.length == 0) {
            history.prices = new uint256[](lookbackBlocks);
            history.timestamps = new uint256[](lookbackBlocks);
        }
        
        // Add to circular buffer
        history.prices[history.head] = price;
        history.timestamps[history.head] = block.timestamp;
        history.head = (history.head + 1) % lookbackBlocks;
        if (history.size < lookbackBlocks) {
            history.size++;
        }
        
        // Check for manipulation patterns
        _checkManipulationPatterns(poolId, history);
    }

    /// @notice Check for potential sandwich attack
    /// @param poolKey The pool
    /// @param expectedPrice Expected execution price
    /// @param actualPrice Actual execution price
    /// @return isSandwich Whether sandwich attack is detected
    function checkForSandwich(
        PoolKey calldata poolKey,
        uint256 expectedPrice,
        uint256 actualPrice
    ) external view returns (bool isSandwich) {
        // Calculate deviation
        uint256 deviationBps = PriceMath.calculateDeviationBps(expectedPrice, actualPrice);
        
        // If deviation is significantly higher than normal, possible sandwich
        // Threshold: 2x the normal max deviation
        return deviationBps > maxDeviationBps * 2;
    }

    // ============ Pool Management ============

    /// @notice Block a pool due to detected manipulation
    /// @param poolKey The pool to block
    /// @param reason Reason for blocking
    function blockPool(PoolKey calldata poolKey, string calldata reason) external onlyOwner {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        blockedPools[poolId] = BlockedPool({
            isBlocked: true,
            blockedAt: block.timestamp,
            reason: reason
        });
        emit PoolBlocked(poolId, reason);
    }

    /// @notice Unblock a pool
    /// @param poolKey The pool to unblock
    function unblockPool(PoolKey calldata poolKey) external onlyOwner {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        delete blockedPools[poolId];
        emit PoolUnblocked(poolId);
    }

    /// @notice Check if pool is blocked
    /// @param poolKey The pool to check
    /// @return isBlocked Whether the pool is blocked
    function isPoolBlocked(PoolKey calldata poolKey) external view returns (bool isBlocked) {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        return blockedPools[poolId].isBlocked;
    }

    // ============ Configuration ============

    /// @notice Set the oracle address
    /// @param _oracle New oracle address
    function setOracle(address _oracle) external onlyOwner {
        oracle = ITWAPOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    /// @notice Set maximum deviation threshold
    /// @param _maxDeviationBps New threshold in bps
    function setMaxDeviation(uint16 _maxDeviationBps) external onlyOwner {
        if (_maxDeviationBps == 0 || _maxDeviationBps > 5000) revert InvalidConfiguration();
        maxDeviationBps = _maxDeviationBps;
        emit MaxDeviationUpdated(_maxDeviationBps);
    }

    /// @notice Set minimum TWAP window
    /// @param _minTWAPWindow New window in blocks
    function setMinTWAPWindow(uint32 _minTWAPWindow) external onlyOwner {
        if (_minTWAPWindow == 0) revert InvalidConfiguration();
        minTWAPWindow = _minTWAPWindow;
        emit TWAPWindowUpdated(_minTWAPWindow);
    }

    /// @notice Set lookback blocks for manipulation detection
    /// @param _lookbackBlocks New lookback period
    function setLookbackBlocks(uint32 _lookbackBlocks) external onlyOwner {
        lookbackBlocks = _lookbackBlocks;
    }

    // ============ View Functions ============

    /// @notice Get price history for a pool
    /// @param poolKey The pool
    /// @return prices Array of historical prices
    /// @return timestamps Array of timestamps
    function getPriceHistory(PoolKey calldata poolKey)
        external
        view
        returns (uint256[] memory prices, uint256[] memory timestamps)
    {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        PriceHistory storage history = priceHistories[poolId];
        
        prices = new uint256[](history.size);
        timestamps = new uint256[](history.size);
        
        for (uint256 i = 0; i < history.size; i++) {
            uint256 idx = (history.head + lookbackBlocks - history.size + i) % lookbackBlocks;
            prices[i] = history.prices[idx];
            timestamps[i] = history.timestamps[idx];
        }
    }

    /// @notice Calculate volatility from price history
    /// @param poolKey The pool
    /// @return volatilityBps Volatility in basis points
    function calculateVolatility(PoolKey calldata poolKey) external view returns (uint256 volatilityBps) {
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        PriceHistory storage history = priceHistories[poolId];
        
        if (history.size < 2) return 0;
        
        uint256 sumDeviation = 0;
        uint256 avgPrice = 0;
        
        // Calculate average
        for (uint256 i = 0; i < history.size; i++) {
            avgPrice += history.prices[i];
        }
        avgPrice /= history.size;
        
        // Calculate standard deviation approximation
        for (uint256 i = 0; i < history.size; i++) {
            uint256 deviation = history.prices[i] > avgPrice 
                ? history.prices[i] - avgPrice 
                : avgPrice - history.prices[i];
            sumDeviation += deviation;
        }
        
        uint256 avgDeviation = sumDeviation / history.size;
        volatilityBps = (avgDeviation * 10000) / avgPrice;
    }

    // ============ Internal Functions ============

    function _checkManipulationPatterns(bytes32 poolId, PriceHistory storage history) internal {
        if (history.size < 3) return;
        
        // Pattern 1: Sudden large price movement followed by reversal (sandwich)
        uint256 latest = history.prices[(history.head + lookbackBlocks - 1) % lookbackBlocks];
        uint256 previous = history.prices[(history.head + lookbackBlocks - 2) % lookbackBlocks];
        uint256 beforePrevious = history.prices[(history.head + lookbackBlocks - 3) % lookbackBlocks];
        
        // Check for V-shape or inverted V-shape pattern
        uint256 move1 = PriceMath.calculateDeviationBps(beforePrevious, previous);
        uint256 move2 = PriceMath.calculateDeviationBps(previous, latest);
        
        // Large move in one direction followed by large move in opposite direction
        bool isVShape = (previous > beforePrevious && latest < previous) ||
                       (previous < beforePrevious && latest > previous);
        
        if (isVShape && move1 > maxDeviationBps * 3 && move2 > maxDeviationBps * 3) {
            blockedPools[poolId] = BlockedPool({
                isBlocked: true,
                blockedAt: block.timestamp,
                reason: "Suspicious price pattern detected"
            });
            emit ManipulationDetected(poolId, latest, beforePrevious, "V-shape price pattern");
            emit PoolBlocked(poolId, "Automatic block: price manipulation pattern");
        }
    }
}
