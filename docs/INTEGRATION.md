# Integration Guide

## Overview

This guide explains how to integrate the TWAP Hook into your DeFi application.

## Prerequisites

- Uniswap v4 deployment on target chain
- TWAP Hook deployed and configured
- User has tokens approved for deposit

## Integration Flow

### 1. Query Available Pools

```solidity
// Get the pool key for your desired pair
PoolKey memory poolKey = PoolKey({
    currency0: Currency.wrap(address(tokenA)),
    currency1: Currency.wrap(address(tokenB)),
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(hookAddress)
});
```

### 2. Calculate Order Parameters

```javascript
// JavaScript/TypeScript
const amountIn = ethers.parseEther("10");
const numChunks = 10;
const intervalBlocks = 5;

// Calculate minimum output (with slippage)
const spotPrice = await oracle.getSpotPrice(poolKey);
const expectedOut = amountIn * spotPrice / 1e18;
const minAmountOut = expectedOut * 95n / 100n; // 5% slippage
```

### 3. Create Order

```solidity
// Solidity
function createTWAPOrder(
    address hook,
    PoolKey memory poolKey,
    uint256 amountIn,
    bool zeroForOne
) external {
    // Approve tokens
    IERC20(inputToken).approve(hook, amountIn);
    
    // Create params
    TWAPTypes.OrderParams memory params = TWAPTypes.OrderParams({
        poolKey: poolKey,
        zeroForOne: zeroForOne,
        amountIn: amountIn,
        minAmountOut: calculateMinOutput(amountIn),
        numChunks: 10,
        intervalBlocks: 5,
        maxSlippageBps: 100,
        deadline: block.timestamp + 1 days,
        recipient: msg.sender
    });
    
    // Create order
    bytes32 orderId = ITWAPHook(hook).createOrder(params);
    
    // Store orderId for tracking
    emit OrderCreated(msg.sender, orderId);
}
```

### 4. Monitor Order Status

```javascript
// Query order status
const order = await hook.getOrder(orderId);

console.log({
    status: order.status,
    chunksExecuted: order.executionState.chunksExecuted,
    totalChunks: order.params.numChunks,
    amountOutSoFar: order.executionState.amountOutAccumulated
});
```

### 5. Cancel Order (if needed)

```solidity
ITWAPHook(hook).cancelOrder(orderId);
// Remaining input refunded, accumulated output transferred
```

## Frontend Integration

### React Example

```typescript
import { useContract, useContractWrite } from "wagmi";

function TWAPOrderForm() {
    const { write: createOrder } = useContractWrite({
        address: HOOK_ADDRESS,
        abi: HOOK_ABI,
        functionName: "createOrder",
    });

    const handleSubmit = async (params: OrderParams) => {
        // Approve tokens first
        await approveTokens(params.amountIn);
        
        // Create order
        const tx = await createOrder([params]);
        await tx.wait();
    };
    
    return (
        <form onSubmit={handleSubmit}>
            {/* Form fields */}
        </form>
    );
}
```

## Event Monitoring

Subscribe to events for real-time updates:

```javascript
hook.on("OrderCreated", (orderId, owner, params) => {
    console.log(`Order ${orderId} created`);
});

hook.on("ChunkExecuted", (orderId, chunkIndex, amountIn, amountOut) => {
    console.log(`Chunk ${chunkIndex} executed for order ${orderId}`);
});

hook.on("OrderCompleted", (orderId, totalAmountOut) => {
    console.log(`Order ${orderId} completed with ${totalAmountOut} output`);
});
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `InvalidOrderParams` | Bad parameters | Validate before submission |
| `CircuitBreakerActive` | System paused | Wait for reset |
| `RateLimitExceeded` | Too many orders | Wait for cooldown |
| `SlippageExceeded` | Price moved too much | Increase slippage or wait |

## Best Practices

1. **Always set reasonable deadlines** - Orders expire if not executed
2. **Use appropriate chunk counts** - More chunks = less impact, longer duration
3. **Monitor gas prices** - High gas may delay execution
4. **Set slippage per chunk** - Not just total slippage
5. **Use commit-reveal for large orders** - Prevents frontrunning
