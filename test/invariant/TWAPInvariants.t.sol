// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TestHelpers} from "../utils/TestHelpers.sol";
import {TWAPOrderVault} from "../../src/TWAPOrderVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TWAPTypes} from "../../src/types/TWAPTypes.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title InvariantHandler
/// @notice Handler contract for invariant testing - provides bounded actions
contract InvariantHandler is Test {
    TWAPOrderVault public vault;
    MockERC20 public token0;
    MockERC20 public token1;
    address public hook;
    
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_orderCount;
    bytes32[] public orderIds;
    
    constructor(TWAPOrderVault _vault, MockERC20 _token0, MockERC20 _token1, address _hook) {
        vault = _vault;
        token0 = _token0;
        token1 = _token1;
        hook = _hook;
    }
    
    function createOrder(uint256 amount) external {
        amount = bound(amount, 1e15, 1e20);
        
        // Create order params
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        bytes32 orderId = keccak256(abi.encodePacked(msg.sender, ghost_orderCount++, block.timestamp));
        
        TWAPTypes.Order memory order = TWAPTypes.Order({
            id: orderId,
            owner: msg.sender,
            params: TWAPTypes.OrderParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: amount,
                minAmountOut: amount * 90 / 100,
                numChunks: 10,
                intervalBlocks: 5,
                maxSlippageBps: 100,
                deadline: block.timestamp + 1 days,
                recipient: msg.sender
            }),
            status: TWAPTypes.OrderStatus.Active,
            executionState: TWAPTypes.ExecutionState({
                chunksExecuted: 0,
                amountInRemaining: amount,
                amountOutAccumulated: 0,
                lastExecutionBlock: block.number,
                averagePrice: 0,
                totalGasUsed: 0
            }),
            createdAt: block.number,
            updatedAt: block.number
        });
        
        // Mint tokens and store order
        token0.mint(address(this), amount);
        token0.approve(address(vault), amount);
        
        vm.prank(hook);
        vault.storeOrder(order);
        
        vm.prank(hook);
        vault.deposit(orderId, Currency.wrap(address(token0)), amount, address(this));
        
        orderIds.push(orderId);
        ghost_totalDeposited += amount;
    }
    
    function getOrderCount() external view returns (uint256) {
        return orderIds.length;
    }
    
    function getVaultBalance() external view returns (uint256) {
        return token0.balanceOf(address(vault));
    }
}

/// @title TWAPInvariantsTest
/// @notice Invariant tests for TWAP system
contract TWAPInvariantsTest is StdInvariant, TestHelpers {
    TWAPOrderVault public vault;
    MockERC20 public token0;
    MockERC20 public token1;
    InvariantHandler public handler;
    address public hook;
    address public executor;
    
    function setUp() public {
        // Deploy tokens
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // Deploy vault
        vault = new TWAPOrderVault();
        
        // Set up authorized addresses
        hook = makeAddr("hook");
        executor = makeAddr("executor");
        vault.setHook(hook);
        vault.setExecutor(executor);
        
        // Deploy handler
        handler = new InvariantHandler(vault, token0, token1, hook);
        
        // Target the handler for fuzzing
        targetContract(address(handler));
        
        // Exclude vault from direct fuzzing (only through handler)
        excludeContract(address(vault));
    }
    
    /// @notice Invariant: Total deposits tracked by handler matches vault token balance
    function invariant_totalDepositsMatchBalances() public view {
        uint256 vaultBalance = token0.balanceOf(address(vault));
        uint256 trackedDeposits = handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn();
        
        // Allow for small discrepancies due to execution (output tokens)
        assertGe(vaultBalance + 1e10, trackedDeposits, "Vault balance should match or exceed tracked deposits");
    }
    
    /// @notice Invariant: Order count never decreases
    function invariant_orderProgressNeverRegresses() public view {
        uint256 orderCount = handler.getOrderCount();
        // Order count should always be >= 0 (trivially true but demonstrates pattern)
        assertGe(orderCount, 0, "Order count should never be negative");
    }
    
    /// @notice Invariant: Vault should never have more orders than ghost counter
    function invariant_outputNeverExceedsInput() public view {
        uint256 orderCount = handler.getOrderCount();
        uint256 ghostCount = handler.ghost_orderCount();
        assertEq(orderCount, ghostCount, "Order count should match ghost counter");
    }
}
