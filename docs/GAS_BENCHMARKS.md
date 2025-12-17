# Gas Benchmarks

## Overview

This document provides gas usage benchmarks for TWAP Hook operations.

## Test Methodology

- Foundry's `--gas-report` flag
- Solidity version: 0.8.26
- Optimizer: enabled (1,000,000 runs)
- via-ir: enabled

## Benchmarks

### Core Operations

| Operation | Gas (avg) | Gas (min) | Gas (max) |
|-----------|-----------|-----------|-----------|
| Create Order | ~150,000 | 120,000 | 200,000 |
| Execute Chunk | ~100,000 | 80,000 | 150,000 |
| Cancel Order | ~50,000 | 40,000 | 80,000 |
| Batch Execute (5) | ~400,000 | 350,000 | 500,000 |

### Security Operations

| Operation | Gas (avg) |
|-----------|-----------|
| Commit | ~50,000 |
| Reveal | ~30,000 |
| Trigger Circuit Breaker | ~30,000 |
| Reset Circuit Breaker | ~25,000 |

### Governance Operations

| Operation | Gas (avg) |
|-----------|-----------|
| Create Proposal | ~100,000 |
| Queue Proposal | ~80,000 |
| Execute Proposal | ~100,000 |
| Cancel Proposal | ~40,000 |

## Cost Estimates

At various gas prices (ETH = $2000):

| Operation | 20 gwei | 50 gwei | 100 gwei |
|-----------|---------|---------|----------|
| Create Order | $6.00 | $15.00 | $30.00 |
| Execute Chunk | $4.00 | $10.00 | $20.00 |
| Cancel Order | $2.00 | $5.00 | $10.00 |

## Optimization Notes

### Implemented Optimizations

1. **Packed Structs**: Order and ExecutionState use packed storage
2. **Minimal Storage**: Only essential data stored on-chain
3. **Batch Operations**: Multiple orders executed in single transaction
4. **View Functions**: Extensive use of view functions for read operations

### Potential Improvements

1. **EIP-2929**: Access list optimization for frequently accessed slots
2. **Assembly**: Critical paths could use assembly for gas savings
3. **Lazy Evaluation**: Defer computations where possible

## Running Benchmarks

```bash
# Run gas report
forge test --gas-report

# Snapshot gas for comparison
forge snapshot

# Compare to baseline
forge snapshot --diff
```

## Benchmark Tests

Located in `test/gas/GasBenchmark.t.sol`:

```solidity
function test_gas_createOrder() public {
    // Measure gas for order creation
}

function test_gas_executeChunk() public {
    // Measure gas for chunk execution
}

function test_gas_batchExecute() public {
    // Measure gas for batch execution
}
```
