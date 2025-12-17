// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TWAPTypes} from "../../src/types/TWAPTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title TestHelpers
/// @notice Shared test utilities and helpers
abstract contract TestHelpers is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ============ Constants ============

    uint256 internal constant INITIAL_BALANCE = 1000000e18;
    uint256 internal constant DEFAULT_AMOUNT = 10e18;
    uint32 internal constant DEFAULT_CHUNKS = 10;
    uint32 internal constant DEFAULT_INTERVAL = 5;
    uint16 internal constant DEFAULT_SLIPPAGE = 100; // 1%
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 1:1 price

    // ============ Test Accounts ============

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");
    address internal guardian = makeAddr("guardian");
    address internal admin = makeAddr("admin");

    // ============ Pool Key Helpers ============

    function createPoolKey(
        address token0,
        address token1,
        address hooks
    ) internal pure returns (PoolKey memory key) {
        // Ensure token0 < token1 for Uniswap ordering
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hooks)
        });
    }

    function createPoolKeyWithNativeETH(
        address token,
        address hooks
    ) internal pure returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hooks)
        });
    }

    // ============ Order Helpers ============

    function createDefaultOrderParams(
        PoolKey memory poolKey,
        bool zeroForOne,
        address recipient
    ) internal view returns (TWAPTypes.OrderParams memory params) {
        params = TWAPTypes.OrderParams({
            poolKey: poolKey,
            zeroForOne: zeroForOne,
            amountIn: DEFAULT_AMOUNT,
            minAmountOut: DEFAULT_AMOUNT * 95 / 100, // 5% slippage
            numChunks: DEFAULT_CHUNKS,
            intervalBlocks: DEFAULT_INTERVAL,
            maxSlippageBps: DEFAULT_SLIPPAGE,
            deadline: block.timestamp + 1 days,
            recipient: recipient
        });
    }

    function createOrderParams(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint32 numChunks,
        uint32 intervalBlocks,
        address recipient
    ) internal view returns (TWAPTypes.OrderParams memory params) {
        params = TWAPTypes.OrderParams({
            poolKey: poolKey,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            minAmountOut: amountIn * 90 / 100,
            numChunks: numChunks,
            intervalBlocks: intervalBlocks,
            maxSlippageBps: DEFAULT_SLIPPAGE,
            deadline: block.timestamp + 1 days,
            recipient: recipient
        });
    }

    // ============ Config Helpers ============

    function createDefaultConfig() internal pure returns (TWAPTypes.Config memory config) {
        config = TWAPTypes.Config({
            minChunkSize: 1e15,
            maxChunkSize: 1e24,
            minIntervalBlocks: 1,
            maxIntervalBlocks: 1000,
            maxOrderDuration: 50000,
            commitRevealDelay: 2,
            maxSlippageBps: 500,
            protocolFeeBps: 10
        });
    }

    // ============ Token Helpers ============

    function deployToken(
        string memory name,
        string memory symbol
    ) internal returns (MockERC20 token) {
        token = new MockERC20(name, symbol, 18);
    }

    function mintAndApprove(
        MockERC20 token,
        address user,
        address spender,
        uint256 amount
    ) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(spender, amount);
    }

    // ============ Block Manipulation ============

    function advanceBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    function advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function advanceBlocksAndTime(uint256 blocks, uint256 seconds_) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + seconds_);
    }

    // ============ Logging Helpers ============

    function logPoolId(PoolKey memory key) internal pure returns (bytes32) {
        return PoolId.unwrap(key.toId());
    }

    function logOrder(TWAPTypes.Order memory order) internal view {
        console.log("Order ID:", vm.toString(order.id));
        console.log("Owner:", order.owner);
        console.log("Status:", uint256(order.status));
        console.log("Chunks Executed:", order.executionState.chunksExecuted);
        console.log("Amount In Remaining:", order.executionState.amountInRemaining);
        console.log("Amount Out Accumulated:", order.executionState.amountOutAccumulated);
    }

    // ============ Assertion Helpers ============

    function assertOrderStatus(
        TWAPTypes.Order memory order,
        TWAPTypes.OrderStatus expected
    ) internal pure {
        assertEq(uint256(order.status), uint256(expected), "Unexpected order status");
    }

    function assertOrderProgress(
        TWAPTypes.Order memory order,
        uint32 expectedChunksExecuted
    ) internal pure {
        assertEq(order.executionState.chunksExecuted, expectedChunksExecuted, "Unexpected chunks executed");
    }

    // ============ Fuzz Bounds ============

    function boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 1e15, 1e24);
    }

    function boundChunks(uint32 chunks) internal pure returns (uint32) {
        return uint32(bound(chunks, 2, 100));
    }

    function boundInterval(uint32 interval) internal pure returns (uint32) {
        return uint32(bound(interval, 1, 100));
    }

    function boundSlippage(uint16 slippage) internal pure returns (uint16) {
        return uint16(bound(slippage, 1, 500));
    }

    // ============ Event Helpers ============

    function expectEmitOrderCreated() internal {
        vm.expectEmit(true, true, false, false);
    }

    function expectEmitChunkExecuted() internal {
        vm.expectEmit(true, true, false, false);
    }
}
