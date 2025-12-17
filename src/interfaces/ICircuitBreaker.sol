// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ICircuitBreaker
/// @notice Interface for the Circuit Breaker - emergency stop mechanism
interface ICircuitBreaker {
    // ============ Circuit Breaker Controls ============

    /// @notice Trigger the circuit breaker (emergency stop)
    /// @param reason Description of why it was triggered
    function trigger(string calldata reason) external;

    /// @notice Reset the circuit breaker (resume operations)
    function reset() external;

    /// @notice Check if circuit breaker is active
    /// @return isTriggered Whether the circuit breaker is triggered
    function isTriggered() external view returns (bool isTriggered);

    /// @notice Get circuit breaker status details
    /// @return triggered Whether currently triggered
    /// @return triggeredAt Timestamp when triggered
    /// @return triggeredBy Address that triggered it
    /// @return reason Reason for triggering
    function getStatus()
        external
        view
        returns (bool triggered, uint256 triggeredAt, address triggeredBy, string memory reason);

    // ============ Auto-Trigger Conditions ============

    /// @notice Set price deviation threshold for auto-trigger
    /// @param thresholdBps Threshold in basis points
    function setPriceDeviationThreshold(uint16 thresholdBps) external;

    /// @notice Set volume spike threshold for auto-trigger
    /// @param multiplier Volume multiplier threshold (e.g., 10 = 10x normal)
    function setVolumeSpikeThreshold(uint256 multiplier) external;

    /// @notice Set maximum consecutive failed executions before trigger
    /// @param maxFailures Maximum allowed failures
    function setMaxConsecutiveFailures(uint32 maxFailures) external;

    /// @notice Report a failed execution (for auto-trigger tracking)
    /// @param orderId The order that failed
    function reportFailure(bytes32 orderId) external;

    /// @notice Report a successful execution (resets failure counter)
    /// @param orderId The order that succeeded
    function reportSuccess(bytes32 orderId) external;

    // ============ Access Control ============

    /// @notice Add a guardian who can trigger the circuit breaker
    /// @param guardian Address to add as guardian
    function addGuardian(address guardian) external;

    /// @notice Remove a guardian
    /// @param guardian Address to remove
    function removeGuardian(address guardian) external;

    /// @notice Check if an address is a guardian
    /// @param account Address to check
    /// @return isGuardian Whether the address is a guardian
    function isGuardian(address account) external view returns (bool isGuardian);

    /// @notice Get all guardians
    /// @return guardians Array of guardian addresses
    function getGuardians() external view returns (address[] memory guardians);

    // ============ Configuration Queries ============

    /// @notice Get price deviation threshold
    /// @return thresholdBps Threshold in basis points
    function getPriceDeviationThreshold() external view returns (uint16 thresholdBps);

    /// @notice Get volume spike threshold
    /// @return multiplier Volume multiplier threshold
    function getVolumeSpikeThreshold() external view returns (uint256 multiplier);

    /// @notice Get max consecutive failures setting
    /// @return maxFailures Maximum failures before trigger
    function getMaxConsecutiveFailures() external view returns (uint32 maxFailures);

    /// @notice Get current consecutive failure count
    /// @return failures Current failure count
    function getConsecutiveFailures() external view returns (uint32 failures);

    // ============ Cooldown ============

    /// @notice Set cooldown period after reset
    /// @param cooldownSeconds Cooldown duration in seconds
    function setCooldown(uint256 cooldownSeconds) external;

    /// @notice Get remaining cooldown time
    /// @return remaining Remaining cooldown in seconds
    function getRemainingCooldown() external view returns (uint256 remaining);

    // ============ Events ============

    event CircuitBreakerTriggered(address indexed triggeredBy, string reason, uint256 timestamp);
    event CircuitBreakerReset(address indexed resetBy, uint256 timestamp);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event PriceDeviationThresholdUpdated(uint16 newThreshold);
    event VolumeSpikeThresholdUpdated(uint256 newMultiplier);
    event MaxConsecutiveFailuresUpdated(uint32 newMax);
    event CooldownUpdated(uint256 newCooldown);
    event FailureReported(bytes32 indexed orderId, uint32 consecutiveFailures);
}
