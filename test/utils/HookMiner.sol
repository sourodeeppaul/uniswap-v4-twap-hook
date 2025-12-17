// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title HookMiner
/// @notice Utility for mining hook addresses with specific permission flags
/// @dev Uniswap v4 hooks must have specific address bits set for permissions
library HookMiner {
    /// @notice Find a salt that produces a hook address with desired flags
    /// @param deployer The address deploying the hook
    /// @param flags The desired hook permission flags
    /// @param creationCode The creation bytecode of the hook contract
    /// @param constructorArgs The encoded constructor arguments
    /// @param seed Starting seed for mining
    /// @return hookAddress The mined hook address
    /// @return salt The salt that produces this address
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 seed
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        bytes32 creationCodeHash = keccak256(creationCodeWithArgs);
        
        for (uint256 i = seed; i < seed + 10000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, creationCodeHash);
            
            if (hasCorrectFlags(hookAddress, flags)) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: could not find salt");
    }

    /// @notice Find a salt with extended search range
    function findExtended(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 seed,
        uint256 maxAttempts
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        bytes32 creationCodeHash = keccak256(creationCodeWithArgs);
        
        for (uint256 i = seed; i < seed + maxAttempts; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, creationCodeHash);
            
            if (hasCorrectFlags(hookAddress, flags)) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: could not find salt");
    }

    /// @notice Compute CREATE2 address
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes32 creationCodeHash
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            creationCodeHash
                        )
                    )
                )
            )
        );
    }

    /// @notice Check if address has correct hook flags
    /// @dev Hook permissions are encoded in the lower 14 bits of the address
    function hasCorrectFlags(address hookAddress, uint160 flags) internal pure returns (bool) {
        // The lower 14 bits must match the flags
        uint160 addressFlags = uint160(hookAddress) & uint160(0x3FFF);
        return addressFlags == flags;
    }

    /// @notice Get hook flags from address
    function getFlags(address hookAddress) internal pure returns (uint160) {
        return uint160(hookAddress) & uint160(0x3FFF);
    }

    // ============ Flag Constants ============

    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 0;
    uint160 internal constant AFTER_INITIALIZE_FLAG = 1 << 1;
    uint160 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 2;
    uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 3;
    uint160 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 4;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 5;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 6;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 7;
    uint160 internal constant BEFORE_DONATE_FLAG = 1 << 8;
    uint160 internal constant AFTER_DONATE_FLAG = 1 << 9;
    uint160 internal constant BEFORE_SWAP_RETURN_DELTA_FLAG = 1 << 10;
    uint160 internal constant AFTER_SWAP_RETURN_DELTA_FLAG = 1 << 11;
    uint160 internal constant AFTER_ADD_LIQUIDITY_RETURN_DELTA_FLAG = 1 << 12;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_RETURN_DELTA_FLAG = 1 << 13;

    /// @notice Get flags for TWAP hook (beforeSwap + afterSwap)
    function getTWAPHookFlags() internal pure returns (uint160) {
        return BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG;
    }
}
