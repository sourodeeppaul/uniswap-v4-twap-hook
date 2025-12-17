// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title ITWAPOracle
/// @notice Interface for the TWAP Oracle - provides price data for execution
interface ITWAPOracle {
    // ============ TWAP Queries ============

    /// @notice Get TWAP price over a specified window
    /// @param poolKey The pool to query
    /// @param windowBlocks Number of blocks for TWAP calculation
    /// @return result The TWAP calculation result
    function getTWAP(PoolKey calldata poolKey, uint32 windowBlocks)
        external
        view
        returns (TWAPTypes.TWAPResult memory result);

    /// @notice Get TWAP price between two block numbers
    /// @param poolKey The pool to query
    /// @param startBlock Start block for calculation
    /// @param endBlock End block for calculation
    /// @return result The TWAP calculation result
    function getTWAPBetweenBlocks(PoolKey calldata poolKey, uint256 startBlock, uint256 endBlock)
        external
        view
        returns (TWAPTypes.TWAPResult memory result);

    // ============ Spot Price ============

    /// @notice Get current spot price
    /// @param poolKey The pool to query
    /// @return price Current spot price
    function getSpotPrice(PoolKey calldata poolKey) external view returns (uint256 price);

    /// @notice Get price with timestamp
    /// @param poolKey The pool to query
    /// @return pricePoint Full price point data
    function getPricePoint(PoolKey calldata poolKey) external view returns (TWAPTypes.PricePoint memory pricePoint);

    // ============ Price Validation ============

    /// @notice Check if current price is within acceptable deviation from TWAP
    /// @param poolKey The pool to check
    /// @param maxDeviationBps Maximum allowed deviation in basis points
    /// @return isValid Whether price is within bounds
    /// @return currentPrice Current spot price
    /// @return twapPrice TWAP price
    function validatePrice(PoolKey calldata poolKey, uint16 maxDeviationBps)
        external
        view
        returns (bool isValid, uint256 currentPrice, uint256 twapPrice);

    /// @notice Check for potential price manipulation
    /// @param poolKey The pool to check
    /// @return isManipulated Whether manipulation is detected
    /// @return confidence Confidence score of detection
    function detectManipulation(PoolKey calldata poolKey)
        external
        view
        returns (bool isManipulated, uint256 confidence);

    // ============ Oracle Configuration ============

    /// @notice Set the TWAP observation window
    /// @param windowBlocks Number of blocks for default TWAP window
    function setDefaultWindow(uint32 windowBlocks) external;

    /// @notice Set the minimum observations required
    /// @param minObservations Minimum number of observations
    function setMinObservations(uint32 minObservations) external;

    /// @notice Add a backup oracle (e.g., Chainlink)
    /// @param feedAddress The oracle feed address
    /// @param feedType Type identifier for the oracle
    function addBackupOracle(address feedAddress, bytes32 feedType) external;

    /// @notice Remove a backup oracle
    /// @param feedAddress The oracle feed to remove
    function removeBackupOracle(address feedAddress) external;

    // ============ View Functions ============

    /// @notice Get the default TWAP window
    /// @return windowBlocks Default window in blocks
    function getDefaultWindow() external view returns (uint32 windowBlocks);

    /// @notice Get minimum required observations
    /// @return minObservations Minimum observations count
    function getMinObservations() external view returns (uint32 minObservations);

    /// @notice Get list of backup oracles
    /// @return oracles Array of backup oracle addresses
    function getBackupOracles() external view returns (address[] memory oracles);

    /// @notice Check if oracle has sufficient data for a pool
    /// @param poolKey The pool to check
    /// @return hasSufficientData Whether enough observations exist
    function hasSufficientData(PoolKey calldata poolKey) external view returns (bool hasSufficientData);

    // ============ Events ============

    event TWAPCalculated(bytes32 indexed poolId, uint256 twapPrice, uint32 windowBlocks, uint32 observations);
    event DefaultWindowUpdated(uint32 newWindow);
    event MinObservationsUpdated(uint32 newMinObservations);
    event BackupOracleAdded(address indexed oracle, bytes32 feedType);
    event BackupOracleRemoved(address indexed oracle);
    event ManipulationDetected(bytes32 indexed poolId, uint256 spotPrice, uint256 twapPrice, uint256 deviation);
}
