// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {CommitReveal} from "../../src/security/CommitReveal.sol";
import {TWAPTypes} from "../../src/types/TWAPTypes.sol";
import {TestHelpers} from "../utils/TestHelpers.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

contract CommitRevealTest is TestHelpers {
    CommitReveal public commitReveal;
    PoolKey public poolKey;

    uint32 constant COMMIT_DELAY = 5;
    uint32 constant COMMIT_EXPIRY = 100;

    function setUp() public {
        commitReveal = new CommitReveal(COMMIT_DELAY, COMMIT_EXPIRY, true);
        poolKey = createPoolKey(address(0x1), address(0x2), address(0));
    }

    // ============ Commit Tests ============

    function test_commit_success() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        TWAPTypes.Commitment memory commitment = commitReveal.getCommitment(alice, commitmentHash);
        assertEq(commitment.commitment, commitmentHash);
        assertEq(commitment.commitBlock, block.number);
        assertFalse(commitment.revealed);
    }

    function test_commit_reverts_invalidHash() public {
        vm.prank(alice);
        vm.expectRevert(CommitReveal.InvalidCommitmentHash.selector);
        commitReveal.commit(bytes32(0));
    }

    function test_commit_reverts_alreadyExists() public {
        bytes32 commitmentHash = bytes32(uint256(1));

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        vm.prank(alice);
        vm.expectRevert(CommitReveal.CommitmentAlreadyExists.selector);
        commitReveal.commit(commitmentHash);
    }

    // ============ Reveal Tests ============

    function test_reveal_success() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        // Commit
        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        // Advance blocks
        advanceBlocks(COMMIT_DELAY);

        // Reveal
        vm.prank(alice);
        bool isValid = commitReveal.reveal(params, salt);
        assertTrue(isValid);
    }

    function test_reveal_reverts_tooEarly() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        // Try to reveal immediately
        vm.prank(alice);
        vm.expectRevert();
        commitReveal.reveal(params, salt);
    }

    function test_reveal_reverts_expired() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        // Advance past expiry
        advanceBlocks(COMMIT_EXPIRY + 1);

        vm.prank(alice);
        vm.expectRevert(CommitReveal.CommitmentHasExpired.selector);
        commitReveal.reveal(params, salt);
    }

    function test_reveal_reverts_alreadyRevealed() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        advanceBlocks(COMMIT_DELAY);

        vm.prank(alice);
        commitReveal.reveal(params, salt);

        // Try to reveal again
        vm.prank(alice);
        vm.expectRevert(CommitReveal.CommitmentAlreadyRevealed.selector);
        commitReveal.reveal(params, salt);
    }

    // ============ Can Reveal Tests ============

    function test_canReveal_beforeDelay() public {
        bytes32 commitmentHash = bytes32(uint256(1));

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        (bool canReveal, uint256 blocksRemaining) = commitReveal.canReveal(alice, commitmentHash);
        assertFalse(canReveal);
        assertEq(blocksRemaining, COMMIT_DELAY);
    }

    function test_canReveal_afterDelay() public {
        bytes32 commitmentHash = bytes32(uint256(1));

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        advanceBlocks(COMMIT_DELAY);

        (bool canReveal, uint256 blocksRemaining) = commitReveal.canReveal(alice, commitmentHash);
        assertTrue(canReveal);
        assertEq(blocksRemaining, 0);
    }

    // ============ Admin Tests ============

    function test_setCommitRevealDelay() public {
        uint32 newDelay = 10;
        commitReveal.setCommitRevealDelay(newDelay);
        assertEq(commitReveal.commitRevealDelay(), newDelay);
    }

    function test_setCommitRevealDelay_reverts_zero() public {
        vm.expectRevert(CommitReveal.InvalidDelay.selector);
        commitReveal.setCommitRevealDelay(0);
    }

    function test_setRequired() public {
        commitReveal.setRequired(false);
        assertFalse(commitReveal.isRequired());

        commitReveal.setRequired(true);
        assertTrue(commitReveal.isRequired());
    }

    function test_adminFunctions_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        commitReveal.setCommitRevealDelay(10);

        vm.prank(alice);
        vm.expectRevert();
        commitReveal.setRequired(false);
    }

    // ============ Verification Tests ============

    function test_verifyCommitment_valid() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));
        bytes32 commitmentHash = commitReveal.calculateCommitmentHash(params, salt);

        vm.prank(alice);
        commitReveal.commit(commitmentHash);

        advanceBlocks(COMMIT_DELAY);

        bool isValid = commitReveal.verifyCommitment(alice, params, salt);
        assertTrue(isValid);
    }

    function test_verifyCommitment_invalid_noCommitment() public {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);
        bytes32 salt = bytes32(uint256(12345));

        bool isValid = commitReveal.verifyCommitment(alice, params, salt);
        assertFalse(isValid);
    }
}
