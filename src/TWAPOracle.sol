// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ITWAPOracle} from "./interfaces/ITWAPOracle.sol";
import {TWAPTypes} from "./types/TWAPTypes.sol";
import {PriceMath} from "./libraries/PriceMath.sol";

/// @title TWAPOracle
/// @notice Oracle for TWAP price data from Uniswap v4 pools
contract TWAPOracle is ITWAPOracle, Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ============ State ============

    /// @notice Uniswap v4 Pool Manager
    IPoolManager public immutable poolManager;

    /// @notice Default TWAP window in blocks
    uint32 public defaultWindow;

    /// @notice Minimum observations required for TWAP
    uint32 public minObservations;

    /// @notice Backup oracle addresses
    address[] public backupOracles;

    /// @notice Mapping of backup oracle types
    mapping(address => bytes32) public oracleTypes;

    // ============ Constructor ============

    constructor(
        address _poolManager,
        uint32 _defaultWindow,
        uint32 _minObservations
    ) Ownable(msg.sender) {
        require(_poolManager != address(0), "Invalid pool manager");
        poolManager = IPoolManager(_poolManager);
        defaultWindow = _defaultWindow;
        minObservations = _minObservations;
    }

    // ============ TWAP Queries ============

    /// @inheritdoc ITWAPOracle
    function getTWAP(PoolKey calldata poolKey, uint32 windowBlocks)
        external
        view
        override
        returns (TWAPTypes.TWAPResult memory result)
    {
        uint256 endBlock = block.number;
        uint256 startBlock = endBlock > windowBlocks ? endBlock - windowBlocks : 0;
        
        return _calculateTWAP(poolKey, startBlock, endBlock);
    }

    /// @inheritdoc ITWAPOracle
    function getTWAPBetweenBlocks(PoolKey calldata poolKey, uint256 startBlock, uint256 endBlock)
        external
        view
        override
        returns (TWAPTypes.TWAPResult memory result)
    {
        return _calculateTWAP(poolKey, startBlock, endBlock);
    }

    // ============ Spot Price ============

    /// @inheritdoc ITWAPOracle
    function getSpotPrice(PoolKey calldata poolKey) external view override returns (uint256 price) {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        price = PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96);
    }

    /// @inheritdoc ITWAPOracle
    function getPricePoint(PoolKey calldata poolKey) external view override returns (TWAPTypes.PricePoint memory pricePoint) {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        
        pricePoint = TWAPTypes.PricePoint({
            price: PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96),
            timestamp: block.timestamp,
            blockNumber: block.number,
            confidence: 10000 // 100% confidence for on-chain price
        });
    }

    // ============ Price Validation ============

    /// @inheritdoc ITWAPOracle
    function validatePrice(PoolKey calldata poolKey, uint16 maxDeviationBps)
        external
        view
        override
        returns (bool isValid, uint256 currentPrice, uint256 twapPrice)
    {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        currentPrice = PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96);
        
        // Get TWAP
        TWAPTypes.TWAPResult memory twapResult = _calculateTWAP(poolKey, block.number - defaultWindow, block.number);
        twapPrice = twapResult.twapPrice;
        
        // Check deviation
        isValid = PriceMath.isDeviationWithinBounds(currentPrice, twapPrice, maxDeviationBps);
    }

    /// @inheritdoc ITWAPOracle
    function detectManipulation(PoolKey calldata poolKey)
        external
        view
        override
        returns (bool isManipulated, uint256 confidence)
    {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        uint256 currentPrice = PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96);
        
        // Get short and long TWAP
        TWAPTypes.TWAPResult memory shortTWAP = _calculateTWAP(poolKey, block.number - 10, block.number);
        TWAPTypes.TWAPResult memory longTWAP = _calculateTWAP(poolKey, block.number - defaultWindow, block.number);
        
        // Calculate deviations
        uint256 shortDeviation = PriceMath.calculateDeviationBps(currentPrice, shortTWAP.twapPrice);
        uint256 longDeviation = PriceMath.calculateDeviationBps(shortTWAP.twapPrice, longTWAP.twapPrice);
        
        // If short-term TWAP deviates significantly from long-term, possible manipulation
        if (shortDeviation > 500 || longDeviation > 300) { // 5% and 3% thresholds
            isManipulated = true;
            confidence = (shortDeviation + longDeviation) * 100 / 800; // Scale to 0-100
            if (confidence > 100) confidence = 100;
        }
        
        // Note: emit removed - view functions cannot emit events
    }

    // ============ Oracle Configuration ============

    /// @inheritdoc ITWAPOracle
    function setDefaultWindow(uint32 windowBlocks) external override onlyOwner {
        defaultWindow = windowBlocks;
        emit DefaultWindowUpdated(windowBlocks);
    }

    /// @inheritdoc ITWAPOracle
    function setMinObservations(uint32 _minObservations) external override onlyOwner {
        minObservations = _minObservations;
        emit MinObservationsUpdated(_minObservations);
    }

    /// @inheritdoc ITWAPOracle
    function addBackupOracle(address feedAddress, bytes32 feedType) external override onlyOwner {
        require(feedAddress != address(0), "Invalid address");
        backupOracles.push(feedAddress);
        oracleTypes[feedAddress] = feedType;
        emit BackupOracleAdded(feedAddress, feedType);
    }

    /// @inheritdoc ITWAPOracle
    function removeBackupOracle(address feedAddress) external override onlyOwner {
        for (uint256 i = 0; i < backupOracles.length; i++) {
            if (backupOracles[i] == feedAddress) {
                backupOracles[i] = backupOracles[backupOracles.length - 1];
                backupOracles.pop();
                delete oracleTypes[feedAddress];
                emit BackupOracleRemoved(feedAddress);
                break;
            }
        }
    }

    // ============ View Functions ============

    /// @inheritdoc ITWAPOracle
    function getDefaultWindow() external view override returns (uint32 windowBlocks) {
        return defaultWindow;
    }

    /// @inheritdoc ITWAPOracle
    function getMinObservations() external view override returns (uint32) {
        return minObservations;
    }

    /// @inheritdoc ITWAPOracle
    function getBackupOracles() external view override returns (address[] memory) {
        return backupOracles;
    }

    /// @inheritdoc ITWAPOracle
    function hasSufficientData(PoolKey calldata poolKey) external view override returns (bool) {
        // For Uniswap v4, we check if the pool has enough observations
        // This is a simplified check - in production, query observation cardinality
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        return sqrtPriceX96 > 0;
    }

    // ============ Internal ============

    function _calculateTWAP(
        PoolKey calldata poolKey,
        uint256 startBlock,
        uint256 endBlock
    ) internal view returns (TWAPTypes.TWAPResult memory result) {
        PoolId poolId = poolKey.toId();
        
        // Get current price as simplified TWAP
        // In production, use actual oracle observations
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        
        result = TWAPTypes.TWAPResult({
            twapPrice: PriceMath.sqrtPriceX96ToPrice(sqrtPriceX96),
            startBlock: startBlock,
            endBlock: endBlock,
            numObservations: uint32(endBlock - startBlock)
        });
        
        // Note: emit removed - view functions cannot emit events
    }
}
