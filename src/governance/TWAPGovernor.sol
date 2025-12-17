// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ITWAPHook} from "../interfaces/ITWAPHook.sol";
import {TWAPTypes} from "../types/TWAPTypes.sol";
import {Timelock} from "./Timelock.sol";

/// @title TWAPGovernor
/// @notice Governance contract for TWAP Hook system
/// @dev Manages proposals and configuration changes through timelock
contract TWAPGovernor is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Structs ============

    struct Proposal {
        uint256 id;
        address proposer;
        bytes32 timelockId;
        ProposalType proposalType;
        bytes data;
        uint256 createdAt;
        ProposalStatus status;
        string description;
    }

    enum ProposalType {
        ConfigUpdate,
        EmergencyAction,
        ComponentUpdate,
        ParameterChange
    }

    enum ProposalStatus {
        Pending,
        Queued,
        Executed,
        Cancelled
    }

    // ============ State ============

    /// @notice TWAP Hook contract
    ITWAPHook public hook;

    /// @notice Timelock controller
    Timelock public timelock;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Mapping of proposal ID to proposal
    mapping(uint256 => Proposal) public proposals;

    /// @notice Set of council members
    EnumerableSet.AddressSet private councilMembers;

    /// @notice Minimum council votes required for emergency actions
    uint256 public emergencyThreshold;

    /// @notice Mapping of proposal ID to council votes
    mapping(uint256 => EnumerableSet.AddressSet) private proposalVotes;

    // ============ Events ============

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description
    );
    event ProposalQueued(uint256 indexed proposalId, bytes32 timelockId);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event CouncilMemberAdded(address indexed member);
    event CouncilMemberRemoved(address indexed member);
    event EmergencyThresholdUpdated(uint256 newThreshold);
    event VoteCast(uint256 indexed proposalId, address indexed voter);

    // ============ Errors ============

    error ProposalNotFound();
    error InvalidProposalStatus();
    error NotCouncilMember();
    error ThresholdNotMet();
    error AlreadyVoted();

    // ============ Constructor ============

    constructor(
        address _hook,
        address _timelock,
        address[] memory _initialCouncil,
        uint256 _emergencyThreshold
    ) Ownable(msg.sender) {
        hook = ITWAPHook(_hook);
        timelock = Timelock(payable(_timelock));
        emergencyThreshold = _emergencyThreshold;

        for (uint256 i = 0; i < _initialCouncil.length; i++) {
            councilMembers.add(_initialCouncil[i]);
        }
    }

    // ============ Proposal Creation ============

    /// @notice Propose a configuration update
    /// @param newConfig New configuration
    /// @param description Proposal description
    /// @return proposalId The created proposal ID
    function proposeConfigUpdate(
        TWAPTypes.Config calldata newConfig,
        string calldata description
    ) external onlyOwner returns (uint256 proposalId) {
        proposalId = _createProposal(
            ProposalType.ConfigUpdate,
            abi.encode(newConfig),
            description
        );
    }

    /// @notice Propose a component update
    /// @param vault New vault address (or address(0) to keep current)
    /// @param executor New executor address
    /// @param oracle New oracle address
    /// @param circuitBreaker New circuit breaker address
    /// @param description Proposal description
    /// @return proposalId The created proposal ID
    function proposeComponentUpdate(
        address vault,
        address executor,
        address oracle,
        address circuitBreaker,
        string calldata description
    ) external onlyOwner returns (uint256 proposalId) {
        proposalId = _createProposal(
            ProposalType.ComponentUpdate,
            abi.encode(vault, executor, oracle, circuitBreaker),
            description
        );
    }

    /// @notice Propose an emergency action (requires council votes)
    /// @param target Target contract
    /// @param data Calldata
    /// @param description Action description
    /// @return proposalId The created proposal ID
    function proposeEmergencyAction(
        address target,
        bytes calldata data,
        string calldata description
    ) external returns (uint256 proposalId) {
        require(councilMembers.contains(msg.sender), "Not council member");
        
        proposalId = _createProposal(
            ProposalType.EmergencyAction,
            abi.encode(target, data),
            description
        );
        
        // Auto-vote from proposer
        proposalVotes[proposalId].add(msg.sender);
        emit VoteCast(proposalId, msg.sender);
    }

    // ============ Voting ============

    /// @notice Vote on an emergency proposal
    /// @param proposalId The proposal to vote on
    function voteOnEmergency(uint256 proposalId) external {
        if (!councilMembers.contains(msg.sender)) revert NotCouncilMember();
        
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.proposalType != ProposalType.EmergencyAction) revert InvalidProposalStatus();
        if (proposal.status != ProposalStatus.Pending) revert InvalidProposalStatus();
        if (proposalVotes[proposalId].contains(msg.sender)) revert AlreadyVoted();
        
        proposalVotes[proposalId].add(msg.sender);
        emit VoteCast(proposalId, msg.sender);
        
        // Check if threshold met
        if (proposalVotes[proposalId].length() >= emergencyThreshold) {
            _executeEmergencyAction(proposalId);
        }
    }

    /// @notice Get vote count for a proposal
    /// @param proposalId The proposal ID
    /// @return count Number of votes
    function getVoteCount(uint256 proposalId) external view returns (uint256 count) {
        return proposalVotes[proposalId].length();
    }

    // ============ Proposal Lifecycle ============

    /// @notice Queue a proposal in the timelock
    /// @param proposalId The proposal to queue
    function queueProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.status != ProposalStatus.Pending) revert InvalidProposalStatus();
        
        // Encode the call
        (address target, bytes memory callData) = _getTargetAndCalldata(proposal);
        
        // Schedule in timelock
        bytes32 timelockId = timelock.hashOperation(
            target,
            0,
            callData,
            bytes32(0),
            bytes32(proposalId)
        );
        
        timelock.schedule(
            target,
            0,
            callData,
            bytes32(0),
            bytes32(proposalId),
            timelock.getMinDelay()
        );
        
        proposal.timelockId = timelockId;
        proposal.status = ProposalStatus.Queued;
        
        emit ProposalQueued(proposalId, timelockId);
    }

    /// @notice Execute a queued proposal
    /// @param proposalId The proposal to execute
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.status != ProposalStatus.Queued) revert InvalidProposalStatus();
        
        require(timelock.isOperationReady(proposal.timelockId), "Not ready");
        
        // Execute through timelock
        (address target, bytes memory callData) = _getTargetAndCalldata(proposal);
        
        timelock.execute(
            target,
            0,
            callData,
            bytes32(0),
            bytes32(proposalId)
        );
        
        proposal.status = ProposalStatus.Executed;
        emit ProposalExecuted(proposalId);
    }

    /// @notice Cancel a proposal
    /// @param proposalId The proposal to cancel
    function cancelProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.status == ProposalStatus.Executed) revert InvalidProposalStatus();
        
        if (proposal.status == ProposalStatus.Queued) {
            timelock.cancel(proposal.timelockId);
        }
        
        proposal.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    // ============ Council Management ============

    /// @notice Add a council member
    /// @param member Address to add
    function addCouncilMember(address member) external onlyOwner {
        require(councilMembers.add(member), "Already member");
        emit CouncilMemberAdded(member);
    }

    /// @notice Remove a council member
    /// @param member Address to remove
    function removeCouncilMember(address member) external onlyOwner {
        require(councilMembers.remove(member), "Not member");
        emit CouncilMemberRemoved(member);
    }

    /// @notice Update emergency threshold
    /// @param newThreshold New threshold value
    function setEmergencyThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= councilMembers.length(), "Invalid threshold");
        emergencyThreshold = newThreshold;
        emit EmergencyThresholdUpdated(newThreshold);
    }

    /// @notice Get all council members
    /// @return members Array of council member addresses
    function getCouncilMembers() external view returns (address[] memory members) {
        return councilMembers.values();
    }

    /// @notice Check if address is council member
    /// @param account Address to check
    /// @return isMember Whether address is a council member
    function isCouncilMember(address account) external view returns (bool isMember) {
        return councilMembers.contains(account);
    }

    // ============ View Functions ============

    /// @notice Get proposal details
    /// @param proposalId The proposal ID
    /// @return proposal The proposal details
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
    }

    /// @notice Get time until proposal can be executed
    /// @param proposalId The proposal ID
    /// @return remaining Seconds until executable
    function getTimeUntilExecutable(uint256 proposalId) external view returns (uint256 remaining) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Queued) return 0;
        return timelock.getTimeUntilReady(proposal.timelockId);
    }

    // ============ Internal ============

    function _createProposal(
        ProposalType proposalType,
        bytes memory data,
        string memory description
    ) internal returns (uint256 proposalId) {
        proposalCount++;
        proposalId = proposalCount;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            timelockId: bytes32(0),
            proposalType: proposalType,
            data: data,
            createdAt: block.timestamp,
            status: ProposalStatus.Pending,
            description: description
        });
        
        emit ProposalCreated(proposalId, msg.sender, proposalType, description);
    }

    function _getTargetAndCalldata(Proposal storage proposal) 
        internal 
        view 
        returns (address target, bytes memory callData) 
    {
        if (proposal.proposalType == ProposalType.ConfigUpdate) {
            TWAPTypes.Config memory newConfig = abi.decode(proposal.data, (TWAPTypes.Config));
            target = address(hook);
            callData = abi.encodeWithSelector(ITWAPHook.updateConfig.selector, newConfig);
        } else if (proposal.proposalType == ProposalType.ComponentUpdate) {
            (address vault, address executor, address oracle, address circuitBreaker) = 
                abi.decode(proposal.data, (address, address, address, address));
            target = address(hook);
            // Assuming hook has a setComponents function
            callData = abi.encodeWithSignature(
                "setComponents(address,address,address,address)",
                vault, executor, oracle, circuitBreaker
            );
        } else if (proposal.proposalType == ProposalType.EmergencyAction) {
            (target, callData) = abi.decode(proposal.data, (address, bytes));
        }
    }

    function _executeEmergencyAction(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        (address target, bytes memory data) = abi.decode(proposal.data, (address, bytes));
        
        proposal.status = ProposalStatus.Executed;
        
        (bool success,) = target.call(data);
        require(success, "Emergency action failed");
        
        emit ProposalExecuted(proposalId);
    }
}
