// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title SafeCast
/// @notice Safe type casting library with overflow protection
library SafeCast {
    error SafeCastOverflow(uint256 value, string targetType);

    /// @notice Cast uint256 to uint128
    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) {
            revert SafeCastOverflow(value, "uint128");
        }
        return uint128(value);
    }

    /// @notice Cast uint256 to uint96
    function toUint96(uint256 value) internal pure returns (uint96) {
        if (value > type(uint96).max) {
            revert SafeCastOverflow(value, "uint96");
        }
        return uint96(value);
    }

    /// @notice Cast uint256 to uint64
    function toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert SafeCastOverflow(value, "uint64");
        }
        return uint64(value);
    }

    /// @notice Cast uint256 to uint48
    function toUint48(uint256 value) internal pure returns (uint48) {
        if (value > type(uint48).max) {
            revert SafeCastOverflow(value, "uint48");
        }
        return uint48(value);
    }

    /// @notice Cast uint256 to uint32
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert SafeCastOverflow(value, "uint32");
        }
        return uint32(value);
    }

    /// @notice Cast uint256 to uint16
    function toUint16(uint256 value) internal pure returns (uint16) {
        if (value > type(uint16).max) {
            revert SafeCastOverflow(value, "uint16");
        }
        return uint16(value);
    }

    /// @notice Cast uint256 to uint8
    function toUint8(uint256 value) internal pure returns (uint8) {
        if (value > type(uint8).max) {
            revert SafeCastOverflow(value, "uint8");
        }
        return uint8(value);
    }

    /// @notice Cast int256 to int128
    function toInt128(int256 value) internal pure returns (int128) {
        if (value > type(int128).max || value < type(int128).min) {
            revert SafeCastOverflow(uint256(value > 0 ? value : -value), "int128");
        }
        return int128(value);
    }

    /// @notice Cast int256 to int64
    function toInt64(int256 value) internal pure returns (int64) {
        if (value > type(int64).max || value < type(int64).min) {
            revert SafeCastOverflow(uint256(value > 0 ? value : -value), "int64");
        }
        return int64(value);
    }

    /// @notice Cast uint256 to int256 (safe, no overflow possible for values <= type(int256).max)
    function toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) {
            revert SafeCastOverflow(value, "int256");
        }
        return int256(value);
    }

    /// @notice Cast int256 to uint256 (reverts on negative)
    function toUint256(int256 value) internal pure returns (uint256) {
        if (value < 0) {
            revert SafeCastOverflow(uint256(-value), "uint256 (negative)");
        }
        return uint256(value);
    }
}
