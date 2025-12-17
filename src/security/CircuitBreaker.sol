// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ICircuitBreaker} from "../interfaces/ICircuitBreaker.sol";

/// @title CircuitBreaker
/// @notice Emergency stop mechanism for the TWAP system
/// @dev Guardians can trigger immediately, owner can configure
contract CircuitBreaker is ICircuitBreaker, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ State ============

    /// @notice Whether circuit breaker is currently triggered
    bool private _isTriggered;

    /// @notice When the circuit breaker was triggered
    uint256 public triggeredAt;

    /// @notice Who triggered the circuit breaker
    address public triggeredBy;

    /// @notice Reason for triggering
    string public triggerReason;

    /// @notice Set of guardian addresses
    EnumerableSet.AddressSet private _guardians;

    /// @notice Price deviation threshold for auto-trigger (bps)
    uint16 public priceDeviationThreshold;

    /// @notice Volume spike threshold multiplier
    uint256 public volumeSpikeThreshold;

    /// @notice Max consecutive failures before auto-trigger
    uint32 public maxConsecutiveFailures;

    /// @notice Current consecutive failure count
    uint32 public consecutiveFailures;

    /// @notice Cooldown period after reset (seconds)
    uint256 public cooldownPeriod;

    /// @notice Last reset timestamp
    uint256 public lastResetTime;

    // ============ Modifiers ============

    modifier onlyGuardianOrOwner() {
        require(
            _guardians.contains(msg.sender) || msg.sender == owner(),
            "Not guardian or owner"
        );
        _;
    }

    modifier whenNotTriggered() {
        require(!_isTriggered, "Circuit breaker active");
        _;
    }

    modifier whenTriggered() {
        require(_isTriggered, "Circuit breaker not active");
        _;
    }

    // ============ Constructor ============

    constructor(
        uint16 _priceDeviationThreshold,
        uint256 _volumeSpikeThreshold,
        uint32 _maxConsecutiveFailures,
        uint256 _cooldownPeriod
    ) Ownable(msg.sender) {
        priceDeviationThreshold = _priceDeviationThreshold;
        volumeSpikeThreshold = _volumeSpikeThreshold;
        maxConsecutiveFailures = _maxConsecutiveFailures;
        cooldownPeriod = _cooldownPeriod;
        
        // Owner is initial guardian
        _guardians.add(msg.sender);
    }

    // ============ Circuit Breaker Controls ============

    /// @inheritdoc ICircuitBreaker
    function trigger(string calldata reason) external override onlyGuardianOrOwner whenNotTriggered {
        _trigger(reason);
    }

    /// @inheritdoc ICircuitBreaker
    function reset() external override onlyOwner whenTriggered {
        _isTriggered = false;
        consecutiveFailures = 0;
        lastResetTime = block.timestamp;
        
        emit CircuitBreakerReset(msg.sender, block.timestamp);
    }

    /// @inheritdoc ICircuitBreaker
    function isTriggered() external view override returns (bool) {
        return _isTriggered;
    }

    /// @inheritdoc ICircuitBreaker
    function getStatus()
        external
        view
        override
        returns (bool triggered, uint256 _triggeredAt, address _triggeredBy, string memory reason)
    {
        return (_isTriggered, triggeredAt, triggeredBy, triggerReason);
    }

    // ============ Auto-Trigger Conditions ============

    /// @inheritdoc ICircuitBreaker
    function setPriceDeviationThreshold(uint16 thresholdBps) external override onlyOwner {
        priceDeviationThreshold = thresholdBps;
        emit PriceDeviationThresholdUpdated(thresholdBps);
    }

    /// @inheritdoc ICircuitBreaker
    function setVolumeSpikeThreshold(uint256 multiplier) external override onlyOwner {
        volumeSpikeThreshold = multiplier;
        emit VolumeSpikeThresholdUpdated(multiplier);
    }

    /// @inheritdoc ICircuitBreaker
    function setMaxConsecutiveFailures(uint32 maxFailures) external override onlyOwner {
        maxConsecutiveFailures = maxFailures;
        emit MaxConsecutiveFailuresUpdated(maxFailures);
    }

    /// @inheritdoc ICircuitBreaker
    function reportFailure(bytes32 orderId) external override {
        consecutiveFailures++;
        emit FailureReported(orderId, consecutiveFailures);
        
        // Auto-trigger if threshold reached
        if (maxConsecutiveFailures > 0 && consecutiveFailures >= maxConsecutiveFailures) {
            _trigger("Max consecutive failures reached");
        }
    }

    /// @inheritdoc ICircuitBreaker
    function reportSuccess(bytes32 orderId) external override {
        consecutiveFailures = 0;
        // No event for success to save gas
    }

    /// @notice Check and potentially trigger based on price deviation
    /// @param currentDeviationBps Current price deviation in bps
    function checkPriceDeviation(uint256 currentDeviationBps) external {
        if (priceDeviationThreshold > 0 && currentDeviationBps >= priceDeviationThreshold) {
            _trigger("Price deviation threshold exceeded");
        }
    }

    // ============ Access Control ============

    /// @inheritdoc ICircuitBreaker
    function addGuardian(address guardian) external override onlyOwner {
        require(guardian != address(0), "Invalid guardian");
        require(_guardians.add(guardian), "Already guardian");
        emit GuardianAdded(guardian);
    }

    /// @inheritdoc ICircuitBreaker
    function removeGuardian(address guardian) external override onlyOwner {
        require(_guardians.remove(guardian), "Not a guardian");
        emit GuardianRemoved(guardian);
    }

    /// @inheritdoc ICircuitBreaker
    function isGuardian(address account) external view override returns (bool) {
        return _guardians.contains(account);
    }

    /// @inheritdoc ICircuitBreaker
    function getGuardians() external view override returns (address[] memory guardians) {
        return _guardians.values();
    }

    // ============ Configuration Queries ============

    /// @inheritdoc ICircuitBreaker
    function getPriceDeviationThreshold() external view override returns (uint16 thresholdBps) {
        return priceDeviationThreshold;
    }

    /// @inheritdoc ICircuitBreaker
    function getVolumeSpikeThreshold() external view override returns (uint256 multiplier) {
        return volumeSpikeThreshold;
    }

    /// @inheritdoc ICircuitBreaker
    function getMaxConsecutiveFailures() external view override returns (uint32 maxFailures) {
        return maxConsecutiveFailures;
    }

    /// @inheritdoc ICircuitBreaker
    function getConsecutiveFailures() external view override returns (uint32 failures) {
        return consecutiveFailures;
    }

    // ============ Cooldown ============

    /// @inheritdoc ICircuitBreaker
    function setCooldown(uint256 cooldownSeconds) external override onlyOwner {
        cooldownPeriod = cooldownSeconds;
        emit CooldownUpdated(cooldownSeconds);
    }

    /// @inheritdoc ICircuitBreaker
    function getRemainingCooldown() external view override returns (uint256 remaining) {
        if (lastResetTime == 0) return 0;
        
        uint256 cooldownEnd = lastResetTime + cooldownPeriod;
        if (block.timestamp >= cooldownEnd) return 0;
        
        return cooldownEnd - block.timestamp;
    }

    /// @notice Check if system is in cooldown period
    /// @return inCooldown Whether cooldown is active
    function isInCooldown() external view returns (bool inCooldown) {
        if (lastResetTime == 0) return false;
        return block.timestamp < lastResetTime + cooldownPeriod;
    }

    // ============ Internal ============

    function _trigger(string memory reason) internal {
        _isTriggered = true;
        triggeredAt = block.timestamp;
        triggeredBy = msg.sender;
        triggerReason = reason;
        
        emit CircuitBreakerTriggered(msg.sender, reason, block.timestamp);
    }
}
