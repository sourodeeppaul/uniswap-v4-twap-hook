// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ITWAPOracle} from "../../src/interfaces/ITWAPOracle.sol";
import {TWAPTypes} from "../../src/types/TWAPTypes.sol";

/// @title MockOracle
/// @notice Mock oracle for testing
contract MockOracle is ITWAPOracle {
    // ============ State ============

    uint256 public mockSpotPrice;
    uint256 public mockTWAPPrice;
    uint32 public defaultWindowVal;
    uint32 public minObservationsVal;
    bool public mockValidation;
    bool public mockManipulation;
    address[] public backupOraclesList;

    // ============ Constructor ============

    constructor() {
        mockSpotPrice = 1e18;
        mockTWAPPrice = 1e18;
        defaultWindowVal = 100;
        minObservationsVal = 10;
        mockValidation = true;
        mockManipulation = false;
    }

    // ============ Mock Setters ============

    function setSpotPrice(uint256 price) external {
        mockSpotPrice = price;
    }

    function setTWAPPrice(uint256 price) external {
        mockTWAPPrice = price;
    }

    function setValidation(bool valid) external {
        mockValidation = valid;
    }

    function setManipulation(bool manipulated) external {
        mockManipulation = manipulated;
    }

    // ============ ITWAPOracle Implementation ============

    function getTWAP(PoolKey calldata, uint32 windowBlocks)
        external
        view
        override
        returns (TWAPTypes.TWAPResult memory result)
    {
        result = TWAPTypes.TWAPResult({
            twapPrice: mockTWAPPrice,
            startBlock: block.number - windowBlocks,
            endBlock: block.number,
            numObservations: windowBlocks
        });
    }

    function getTWAPBetweenBlocks(PoolKey calldata, uint256 startBlock, uint256 endBlock)
        external
        view
        override
        returns (TWAPTypes.TWAPResult memory result)
    {
        result = TWAPTypes.TWAPResult({
            twapPrice: mockTWAPPrice,
            startBlock: startBlock,
            endBlock: endBlock,
            numObservations: uint32(endBlock - startBlock)
        });
    }

    function getSpotPrice(PoolKey calldata) external view override returns (uint256 price) {
        return mockSpotPrice;
    }

    function getPricePoint(PoolKey calldata) external view override returns (TWAPTypes.PricePoint memory pricePoint) {
        pricePoint = TWAPTypes.PricePoint({
            price: mockSpotPrice,
            timestamp: block.timestamp,
            blockNumber: block.number,
            confidence: 10000
        });
    }

    function validatePrice(PoolKey calldata, uint16)
        external
        view
        override
        returns (bool isValid, uint256 currentPrice, uint256 twapPrice)
    {
        return (mockValidation, mockSpotPrice, mockTWAPPrice);
    }

    function detectManipulation(PoolKey calldata)
        external
        view
        override
        returns (bool isManipulated, uint256 confidence)
    {
        return (mockManipulation, mockManipulation ? 100 : 0);
    }

    function setDefaultWindow(uint32 windowBlocks) external override {
        defaultWindowVal = windowBlocks;
        emit DefaultWindowUpdated(windowBlocks);
    }

    function setMinObservations(uint32 _minObservations) external override {
        minObservationsVal = _minObservations;
        emit MinObservationsUpdated(_minObservations);
    }

    function addBackupOracle(address feedAddress, bytes32 feedType) external override {
        backupOraclesList.push(feedAddress);
        emit BackupOracleAdded(feedAddress, feedType);
    }

    function removeBackupOracle(address feedAddress) external override {
        for (uint256 i = 0; i < backupOraclesList.length; i++) {
            if (backupOraclesList[i] == feedAddress) {
                backupOraclesList[i] = backupOraclesList[backupOraclesList.length - 1];
                backupOraclesList.pop();
                emit BackupOracleRemoved(feedAddress);
                break;
            }
        }
    }

    function getDefaultWindow() external view override returns (uint32 windowBlocks) {
        return defaultWindowVal;
    }

    function getMinObservations() external view override returns (uint32) {
        return minObservationsVal;
    }

    function getBackupOracles() external view override returns (address[] memory) {
        return backupOraclesList;
    }

    function hasSufficientData(PoolKey calldata) external pure override returns (bool) {
        return true;
    }
}
