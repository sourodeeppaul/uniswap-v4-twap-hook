// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";

/// @title CommitReveal
/// @notice MEV protection via commit-reveal scheme for order placement
/// @dev Users commit a hash of their order, wait for a delay, then reveal
contract CommitReveal is Ownable {
    // ============ State ============

    /// @notice Mapping of user => commitment hash => commitment data
    mapping(address => mapping(bytes32 => TWAPTypes.Commitment)) public commitments;

    /// @notice Minimum blocks to wait between commit and reveal
    uint32 public commitRevealDelay;

    /// @notice Maximum blocks a commitment is valid for
    uint32 public commitmentExpiry;

    /// @notice Whether the commit-reveal is required
    bool public isRequired;

    // ============ Events ============

    event OrderCommitted(address indexed user, bytes32 indexed commitmentHash, uint256 commitBlock);
    event OrderRevealed(address indexed user, bytes32 indexed commitmentHash, bytes32 orderId);
    event CommitmentExpired(address indexed user, bytes32 indexed commitmentHash);
    event DelayUpdated(uint32 newDelay);
    event ExpiryUpdated(uint32 newExpiry);
    event RequirementUpdated(bool isRequired);

    // ============ Errors ============

    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error CommitmentAlreadyRevealed();
    error RevealTooEarly(uint256 currentBlock, uint256 allowedBlock);
    error CommitmentHasExpired();
    error InvalidCommitmentHash();
    error InvalidDelay();

    // ============ Constructor ============

    constructor(
        uint32 _commitRevealDelay,
        uint32 _commitmentExpiry,
        bool _isRequired
    ) Ownable(msg.sender) {
        if (_commitRevealDelay == 0) revert InvalidDelay();
        commitRevealDelay = _commitRevealDelay;
        commitmentExpiry = _commitmentExpiry;
        isRequired = _isRequired;
    }

    // ============ User Functions ============

    /// @notice Commit an order hash
    /// @param commitmentHash Hash of (orderParams, salt)
    function commit(bytes32 commitmentHash) external {
        if (commitmentHash == bytes32(0)) revert InvalidCommitmentHash();
        
        TWAPTypes.Commitment storage existing = commitments[msg.sender][commitmentHash];
        if (existing.commitBlock != 0 && !existing.revealed) {
            // Check if expired
            if (block.number < existing.commitBlock + commitmentExpiry) {
                revert CommitmentAlreadyExists();
            }
        }

        commitments[msg.sender][commitmentHash] = TWAPTypes.Commitment({
            commitment: commitmentHash,
            commitBlock: block.number,
            revealed: false
        });

        emit OrderCommitted(msg.sender, commitmentHash, block.number);
    }

    /// @notice Reveal and validate a commitment
    /// @param orderParams The order parameters
    /// @param salt The salt used in commitment
    /// @return isValid Whether the reveal is valid
    function reveal(
        TWAPTypes.OrderParams calldata orderParams,
        bytes32 salt
    ) external returns (bool isValid) {
        bytes32 commitmentHash = calculateCommitmentHash(orderParams, salt);
        
        TWAPTypes.Commitment storage commitment = commitments[msg.sender][commitmentHash];
        
        // Validate commitment exists
        if (commitment.commitBlock == 0) revert CommitmentNotFound();
        
        // Check not already revealed
        if (commitment.revealed) revert CommitmentAlreadyRevealed();
        
        // Check delay has passed
        uint256 allowedBlock = commitment.commitBlock + commitRevealDelay;
        if (block.number < allowedBlock) {
            revert RevealTooEarly(block.number, allowedBlock);
        }
        
        // Check not expired
        if (block.number > commitment.commitBlock + commitmentExpiry) {
            emit CommitmentExpired(msg.sender, commitmentHash);
            revert CommitmentHasExpired();
        }
        
        // Mark as revealed
        commitment.revealed = true;
        
        emit OrderRevealed(msg.sender, commitmentHash, bytes32(0)); // orderId set later
        
        return true;
    }

    /// @notice Check if a commitment can be revealed
    /// @param user The user address
    /// @param commitmentHash The commitment hash
    /// @return canReveal Whether reveal is possible
    /// @return blocksRemaining Blocks until reveal is allowed
    function canReveal(
        address user,
        bytes32 commitmentHash
    ) external view returns (bool canReveal, uint256 blocksRemaining) {
        TWAPTypes.Commitment storage commitment = commitments[user][commitmentHash];
        
        if (commitment.commitBlock == 0 || commitment.revealed) {
            return (false, 0);
        }
        
        // Check expiry
        if (block.number > commitment.commitBlock + commitmentExpiry) {
            return (false, 0);
        }
        
        uint256 allowedBlock = commitment.commitBlock + commitRevealDelay;
        if (block.number >= allowedBlock) {
            return (true, 0);
        }
        
        return (false, allowedBlock - block.number);
    }

    /// @notice Verify a commitment without revealing
    /// @param user The user address
    /// @param orderParams The order parameters
    /// @param salt The salt
    /// @return isValid Whether commitment exists and is valid
    function verifyCommitment(
        address user,
        TWAPTypes.OrderParams calldata orderParams,
        bytes32 salt
    ) external view returns (bool isValid) {
        bytes32 commitmentHash = calculateCommitmentHash(orderParams, salt);
        TWAPTypes.Commitment storage commitment = commitments[user][commitmentHash];
        
        if (commitment.commitBlock == 0) return false;
        if (commitment.revealed) return false;
        if (block.number > commitment.commitBlock + commitmentExpiry) return false;
        if (block.number < commitment.commitBlock + commitRevealDelay) return false;
        
        return true;
    }

    // ============ View Functions ============

    /// @notice Calculate commitment hash from order params and salt
    /// @param orderParams The order parameters
    /// @param salt Random salt
    /// @return hash The commitment hash
    function calculateCommitmentHash(
        TWAPTypes.OrderParams calldata orderParams,
        bytes32 salt
    ) public pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(orderParams, salt));
    }

    /// @notice Get commitment details
    /// @param user User address
    /// @param commitmentHash The commitment hash
    /// @return commitment The commitment data
    function getCommitment(
        address user,
        bytes32 commitmentHash
    ) external view returns (TWAPTypes.Commitment memory commitment) {
        commitment = commitments[user][commitmentHash];
    }

    /// @notice Check if commit-reveal is required
    /// @return required Whether commit-reveal is mandatory
    function isCommitRevealRequired() external view returns (bool required) {
        return isRequired;
    }

    // ============ Admin Functions ============

    /// @notice Update the commit-reveal delay
    /// @param newDelay New delay in blocks
    function setCommitRevealDelay(uint32 newDelay) external onlyOwner {
        if (newDelay == 0) revert InvalidDelay();
        commitRevealDelay = newDelay;
        emit DelayUpdated(newDelay);
    }

    /// @notice Update commitment expiry
    /// @param newExpiry New expiry in blocks
    function setCommitmentExpiry(uint32 newExpiry) external onlyOwner {
        commitmentExpiry = newExpiry;
        emit ExpiryUpdated(newExpiry);
    }

    /// @notice Set whether commit-reveal is required
    /// @param _isRequired Whether to require commit-reveal
    function setRequired(bool _isRequired) external onlyOwner {
        isRequired = _isRequired;
        emit RequirementUpdated(_isRequired);
    }
}
