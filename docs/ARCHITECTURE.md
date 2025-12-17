# Architecture

## System Overview

The TWAP Hook system consists of multiple interacting contracts that work together to provide time-weighted order execution on Uniswap v4.

## Core Components

### TWAPHook

The main entry point implementing Uniswap v4's `BaseHook`. Handles:
- Order creation and cancellation
- Hook callbacks (`beforeSwap`, `afterSwap`)
- Coordination between components

### TWAPOrderVault

Manages token custody and order storage:
- Secure token deposits
- Order state management
- Balance tracking per order

### TWAPExecutor

Handles trade execution logic:
- Chunk execution
- Slippage protection
- Keeper reward distribution

### TWAPOracle

Provides price data:
- TWAP calculations from pool observations
- Price validation
- Manipulation detection

## Security Components

### CommitReveal

MEV protection through commit-reveal scheme:
1. User commits hash of order parameters
2. Wait for delay period
3. Reveal order and execute

### CircuitBreaker

Emergency stop mechanism:
- Guardian-triggered pause
- Auto-trigger on consecutive failures
- Cooldown period after reset

### RateLimiter

Prevents abuse:
- Per-user rate limits
- Global rate limits
- Sliding window calculations

### PriceGuard

Price manipulation protection:
- TWAP deviation checks
- Pattern detection
- Pool blocking capability

## Data Flow

```
1. Order Creation
   User → CommitReveal → TWAPHook → TWAPOrderVault
         (commit)         (create)   (store + deposit)

2. Order Execution
   Keeper → TWAPHook → TWAPExecutor → PoolManager
            (trigger)  (execute)      (swap)

3. Output Collection
   TWAPExecutor → TWAPOrderVault → User
   (credit)       (withdraw)       (receive)
```

## State Machine

```
Order States:
  None → Pending → Active → Completed
                      ↓
                 Cancelled/Expired/Failed
```

## Upgrade Path

1. Deploy new implementation
2. Create governance proposal
3. Queue through timelock
4. Execute after delay

## Gas Considerations

- Batch execution supported
- Optimized storage layout
- Minimal on-chain computation
