// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TWAPOrderVault} from "../../src/TWAPOrderVault.sol";
import {TWAPTypes} from "../../src/types/TWAPTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../utils/TestHelpers.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract TWAPOrderVaultTest is TestHelpers {
    TWAPOrderVault public vault;
    MockERC20 public token0;
    MockERC20 public token1;
    PoolKey public poolKey;

    function setUp() public {
        // Deploy vault
        vault = new TWAPOrderVault();

        // Deploy tokens
        token0 = deployToken("Token0", "TK0");
        token1 = deployToken("Token1", "TK1");

        // Create pool key
        poolKey = createPoolKey(address(token0), address(token1), address(0));

        // Set up authorization
        vault.setHook(address(this));
        vault.setExecutor(address(this));

        // Mint tokens
        token0.mint(alice, INITIAL_BALANCE);
        token1.mint(alice, INITIAL_BALANCE);

        vm.prank(alice);
        token0.approve(address(vault), type(uint256).max);
    }

    // ============ Store Order Tests ============

    function test_storeOrder_success() public {
        TWAPTypes.Order memory order = _createTestOrder(bytes32(uint256(1)));

        vault.storeOrder(order);

        TWAPTypes.Order memory stored = vault.getOrder(order.id);
        assertEq(stored.id, order.id);
        assertEq(stored.owner, order.owner);
        assertEq(uint256(stored.status), uint256(TWAPTypes.OrderStatus.Pending));
    }

    function test_storeOrder_reverts_ifExists() public {
        TWAPTypes.Order memory order = _createTestOrder(bytes32(uint256(1)));
        vault.storeOrder(order);

        vm.expectRevert("Order exists");
        vault.storeOrder(order);
    }

    // ============ Deposit Tests ============

    function test_deposit_success() public {
        bytes32 orderId = bytes32(uint256(1));
        uint256 amount = 10e18;

        // Transfer tokens to vault first (simulating hook behavior)
        vm.prank(alice);
        token0.transfer(address(vault), amount);

        vault.deposit(orderId, Currency.wrap(address(token0)), amount, alice);

        assertEq(vault.getInputBalance(orderId), amount);
        assertEq(vault.getTotalDeposits(Currency.wrap(address(token0))), amount);
    }

    function test_deposit_reverts_zeroAmount() public {
        bytes32 orderId = bytes32(uint256(1));

        vm.expectRevert("Zero amount");
        vault.deposit(orderId, Currency.wrap(address(token0)), 0, alice);
    }

    // ============ Withdraw Tests ============

    function test_withdraw_success() public {
        bytes32 orderId = bytes32(uint256(1));
        uint256 amount = 10e18;

        // Setup: deposit first
        vm.prank(alice);
        token0.transfer(address(vault), amount);
        vault.deposit(orderId, Currency.wrap(address(token0)), amount, alice);

        // Withdraw
        uint256 withdrawAmount = 5e18;
        vault.withdraw(orderId, Currency.wrap(address(token0)), withdrawAmount, bob);

        assertEq(vault.getInputBalance(orderId), amount - withdrawAmount);
        assertEq(token0.balanceOf(bob), withdrawAmount);
    }

    function test_withdraw_reverts_insufficientBalance() public {
        bytes32 orderId = bytes32(uint256(1));
        uint256 amount = 10e18;

        vm.prank(alice);
        token0.transfer(address(vault), amount);
        vault.deposit(orderId, Currency.wrap(address(token0)), amount, alice);

        vm.expectRevert("Insufficient balance");
        vault.withdraw(orderId, Currency.wrap(address(token0)), amount + 1, bob);
    }

    // ============ Update Order Tests ============

    function test_updateOrder_success() public {
        TWAPTypes.Order memory order = _createTestOrder(bytes32(uint256(1)));
        vault.storeOrder(order);

        TWAPTypes.ExecutionState memory newState = TWAPTypes.ExecutionState({
            chunksExecuted: 5,
            amountInRemaining: 5e18,
            amountOutAccumulated: 4.9e18,
            lastExecutionBlock: block.number,
            averagePrice: 0.98e18,
            totalGasUsed: 500000
        });

        vault.updateOrder(order.id, TWAPTypes.OrderStatus.Active, newState);

        TWAPTypes.Order memory updated = vault.getOrder(order.id);
        assertEq(uint256(updated.status), uint256(TWAPTypes.OrderStatus.Active));
        assertEq(updated.executionState.chunksExecuted, 5);
    }

    function test_updateOrder_reverts_notFound() public {
        TWAPTypes.ExecutionState memory newState;

        vm.expectRevert("Order not found");
        vault.updateOrder(bytes32(uint256(999)), TWAPTypes.OrderStatus.Active, newState);
    }

    // ============ Query Tests ============

    function test_getUserOrderIds() public {
        // Store multiple orders for alice
        for (uint256 i = 1; i <= 3; i++) {
            TWAPTypes.Order memory order = _createTestOrder(bytes32(i));
            vault.storeOrder(order);
        }

        bytes32[] memory orderIds = vault.getUserOrderIds(alice);
        assertEq(orderIds.length, 3);
    }

    function test_getActiveOrderCount() public {
        // Store orders
        for (uint256 i = 1; i <= 5; i++) {
            TWAPTypes.Order memory order = _createTestOrder(bytes32(i));
            vault.storeOrder(order);
        }

        assertEq(vault.getActiveOrderCount(), 5);

        // Cancel one
        TWAPTypes.ExecutionState memory state;
        vault.updateOrder(bytes32(uint256(1)), TWAPTypes.OrderStatus.Cancelled, state);

        assertEq(vault.getActiveOrderCount(), 4);
    }

    // ============ Access Control Tests ============

    function test_setHook_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setHook(alice);
    }

    function test_setExecutor_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setExecutor(alice);
    }

    function test_deposit_onlyHook() public {
        vault.setHook(address(0x123));

        vm.expectRevert("Only hook");
        vault.deposit(bytes32(uint256(1)), Currency.wrap(address(token0)), 1e18, alice);
    }

    // ============ Helpers ============

    function _createTestOrder(bytes32 id) internal view returns (TWAPTypes.Order memory order) {
        TWAPTypes.OrderParams memory params = createDefaultOrderParams(poolKey, true, alice);

        order = TWAPTypes.Order({
            id: id,
            owner: alice,
            params: params,
            status: TWAPTypes.OrderStatus.Pending,
            executionState: TWAPTypes.ExecutionState({
                chunksExecuted: 0,
                amountInRemaining: params.amountIn,
                amountOutAccumulated: 0,
                lastExecutionBlock: block.number,
                averagePrice: 0,
                totalGasUsed: 0
            }),
            createdAt: block.number,
            updatedAt: block.number
        });
    }
}
