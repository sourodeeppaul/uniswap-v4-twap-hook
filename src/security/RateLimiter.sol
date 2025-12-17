// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title RateLimiter
/// @notice Rate limiting for deposits and executions to prevent abuse
contract RateLimiter is Ownable {
    // ============ Structs ============

    struct UserLimit {
        uint256 amountInWindow;
        uint256 windowStart;
        uint256 cooldownEnd;
    }

    struct GlobalLimit {
        uint256 amountInWindow;
        uint256 windowStart;
    }

    // ============ State ============

    /// @notice Per-user rate limits
    mapping(address => UserLimit) public userLimits;

    /// @notice Global rate limit
    GlobalLimit public globalLimit;

    /// @notice Configuration for rate limiting
    TWAPTypes.RateLimitConfig public config;

    /// @notice Whitelisted addresses (exempt from rate limits)
    mapping(address => bool) public whitelist;

    /// @notice Whether rate limiting is enabled
    bool public isEnabled;

    // ============ Events ============

    event RateLimitConfigUpdated(
        uint256 maxAmountPerWindow,
        uint256 windowDuration,
        uint256 cooldownPeriod
    );
    event UserRateLimitExceeded(address indexed user, uint256 amount, uint256 limit);
    event GlobalRateLimitExceeded(uint256 amount, uint256 limit);
    event AddressWhitelisted(address indexed account);
    event AddressRemovedFromWhitelist(address indexed account);
    event RateLimitingToggled(bool isEnabled);

    // ============ Errors ============

    error UserRateLimitError();
    error GlobalRateLimitError();
    error InCooldown(uint256 cooldownEnd);
    error InvalidConfig();

    // ============ Constructor ============

    constructor(
        uint256 _maxAmountPerWindow,
        uint256 _windowDuration,
        uint256 _cooldownPeriod
    ) Ownable(msg.sender) {
        config = TWAPTypes.RateLimitConfig({
            maxAmountPerWindow: _maxAmountPerWindow,
            windowDuration: _windowDuration,
            cooldownPeriod: _cooldownPeriod
        });
        isEnabled = true;
    }

    // ============ Rate Limiting ============

    /// @notice Check and update rate limit for an amount
    /// @param user User address
    /// @param amount Amount to check
    /// @return allowed Whether the amount is allowed
    function checkAndUpdate(
        address user,
        uint256 amount
    ) external returns (bool allowed) {
        if (!isEnabled || whitelist[user]) {
            return true;
        }

        // Check user limit
        if (!_checkUserLimit(user, amount)) {
            emit UserRateLimitExceeded(user, amount, config.maxAmountPerWindow);
            revert UserRateLimitError();
        }

        // Check global limit
        if (!_checkGlobalLimit(amount)) {
            emit GlobalRateLimitExceeded(amount, config.maxAmountPerWindow * 10);
            revert GlobalRateLimitError();
        }

        // Update limits
        _updateUserLimit(user, amount);
        _updateGlobalLimit(amount);

        return true;
    }

    /// @notice Check if amount is within limits (view only)
    /// @param user User address
    /// @param amount Amount to check
    /// @return withinLimit Whether amount is within limits
    /// @return availableAmount Amount still available in window
    function checkLimit(
        address user,
        uint256 amount
    ) external view returns (bool withinLimit, uint256 availableAmount) {
        if (!isEnabled || whitelist[user]) {
            return (true, type(uint256).max);
        }

        UserLimit storage userLimit = userLimits[user];
        
        // Check cooldown
        if (block.timestamp < userLimit.cooldownEnd) {
            return (false, 0);
        }

        // Calculate available amount
        uint256 currentAmount = _getCurrentWindowAmount(userLimit);
        if (currentAmount >= config.maxAmountPerWindow) {
            return (false, 0);
        }

        availableAmount = config.maxAmountPerWindow - currentAmount;
        withinLimit = amount <= availableAmount;
    }

    /// @notice Get remaining allowance for user
    /// @param user User address
    /// @return remaining Remaining amount in current window
    function getRemainingAllowance(address user) external view returns (uint256 remaining) {
        if (!isEnabled || whitelist[user]) {
            return type(uint256).max;
        }

        UserLimit storage userLimit = userLimits[user];
        uint256 currentAmount = _getCurrentWindowAmount(userLimit);
        
        if (currentAmount >= config.maxAmountPerWindow) {
            return 0;
        }
        
        return config.maxAmountPerWindow - currentAmount;
    }

    /// @notice Get time until rate limit resets
    /// @param user User address
    /// @return timeUntilReset Seconds until window resets
    function getTimeUntilReset(address user) external view returns (uint256 timeUntilReset) {
        UserLimit storage userLimit = userLimits[user];
        
        if (userLimit.windowStart == 0) {
            return 0;
        }
        
        uint256 windowEnd = userLimit.windowStart + config.windowDuration;
        if (block.timestamp >= windowEnd) {
            return 0;
        }
        
        return windowEnd - block.timestamp;
    }

    // ============ Admin Functions ============

    /// @notice Update rate limit configuration
    /// @param newConfig New configuration
    function updateConfig(TWAPTypes.RateLimitConfig calldata newConfig) external onlyOwner {
        if (newConfig.windowDuration == 0) revert InvalidConfig();
        config = newConfig;
        emit RateLimitConfigUpdated(
            newConfig.maxAmountPerWindow,
            newConfig.windowDuration,
            newConfig.cooldownPeriod
        );
    }

    /// @notice Add address to whitelist
    /// @param account Address to whitelist
    function addToWhitelist(address account) external onlyOwner {
        whitelist[account] = true;
        emit AddressWhitelisted(account);
    }

    /// @notice Remove address from whitelist
    /// @param account Address to remove
    function removeFromWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
        emit AddressRemovedFromWhitelist(account);
    }

    /// @notice Toggle rate limiting on/off
    /// @param _isEnabled Whether to enable rate limiting
    function setEnabled(bool _isEnabled) external onlyOwner {
        isEnabled = _isEnabled;
        emit RateLimitingToggled(_isEnabled);
    }

    /// @notice Reset a user's rate limit (admin override)
    /// @param user User to reset
    function resetUserLimit(address user) external onlyOwner {
        delete userLimits[user];
    }

    /// @notice Reset global rate limit (admin override)
    function resetGlobalLimit() external onlyOwner {
        delete globalLimit;
    }

    // ============ Internal Functions ============

    function _checkUserLimit(address user, uint256 amount) internal view returns (bool) {
        UserLimit storage userLimit = userLimits[user];
        
        // Check cooldown
        if (block.timestamp < userLimit.cooldownEnd) {
            return false;
        }
        
        uint256 currentAmount = _getCurrentWindowAmount(userLimit);
        return currentAmount + amount <= config.maxAmountPerWindow;
    }

    function _checkGlobalLimit(uint256 amount) internal view returns (bool) {
        uint256 globalMax = config.maxAmountPerWindow * 10; // 10x user limit
        
        GlobalLimit storage gl = globalLimit;
        
        // Check if window expired
        if (block.timestamp >= gl.windowStart + config.windowDuration) {
            return amount <= globalMax;
        }
        
        return gl.amountInWindow + amount <= globalMax;
    }

    function _updateUserLimit(address user, uint256 amount) internal {
        UserLimit storage userLimit = userLimits[user];
        
        // Reset if window expired
        if (block.timestamp >= userLimit.windowStart + config.windowDuration) {
            userLimit.windowStart = block.timestamp;
            userLimit.amountInWindow = amount;
        } else {
            userLimit.amountInWindow += amount;
        }
        
        // Set cooldown if limit reached
        if (userLimit.amountInWindow >= config.maxAmountPerWindow) {
            userLimit.cooldownEnd = block.timestamp + config.cooldownPeriod;
        }
    }

    function _updateGlobalLimit(uint256 amount) internal {
        GlobalLimit storage gl = globalLimit;
        
        // Reset if window expired
        if (block.timestamp >= gl.windowStart + config.windowDuration) {
            gl.windowStart = block.timestamp;
            gl.amountInWindow = amount;
        } else {
            gl.amountInWindow += amount;
        }
    }

    function _getCurrentWindowAmount(UserLimit storage userLimit) internal view returns (uint256) {
        // If window expired, current amount is 0
        if (block.timestamp >= userLimit.windowStart + config.windowDuration) {
            return 0;
        }
        return userLimit.amountInWindow;
    }
}
