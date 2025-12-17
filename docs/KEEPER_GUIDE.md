# Keeper Guide

## Overview

Keepers are off-chain bots that monitor the TWAP Hook for executable orders and submit transactions to execute them. In return, keepers earn a reward from each successful execution.

## Getting Started

### Requirements

- Node.js >= 18
- Funded Ethereum wallet
- Access to an RPC endpoint

### Setup

```bash
cd keeper
npm install
cp .env.example .env
# Edit .env with your configuration
```

### Configuration

```bash
# Required
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
CHAIN_ID=1
HOOK_ADDRESS=0x...
EXECUTOR_ADDRESS=0x...
KEEPER_PRIVATE_KEY=0x...

# Optional (with defaults)
MAX_GAS_PRICE=100000000000  # 100 gwei
GAS_LIMIT=500000
POLL_INTERVAL_MS=12000      # ~1 block
MAX_ORDERS_PER_BATCH=10
MAX_RETRIES=3
```

### Running

```bash
# Development
npm run dev

# Production
npm run build
npm start
```

## Operation

### Execution Loop

1. Poll for executable orders
2. Simulate execution for profitability
3. Submit transaction(s)
4. Monitor for confirmation
5. Record metrics

### Profitability

Keeper rewards are configured as a percentage of output:
- Default: 10 bps (0.1%)
- Maximum: 500 bps (5%)

Calculate profitability:
```
profit = (outputAmount * rewardBps / 10000) - gasCost
```

### Gas Management

- Set `MAX_GAS_PRICE` to avoid executing during high gas
- Batch multiple orders in single transaction when possible
- Monitor gas prices and adjust dynamically

## Monitoring

### Metrics

The keeper tracks:
- Block number
- Wallet balance
- Pending order count
- Success/failure counts
- Total gas used

### Logging

Logs are written to stdout. Use a log aggregator for production:
```bash
npm start 2>&1 | tee -a keeper.log
```

### Alerts

Set up alerts for:
- Low wallet balance
- High failure rate
- No orders found for extended period
- Connection issues

## Troubleshooting

### No Orders Found

- Check that orders exist and are past their interval
- Verify hook address is correct
- Check RPC connection

### Transaction Failures

- Increase gas limit
- Check slippage settings
- Verify circuit breaker is not active

### High Gas

- Wait for lower gas periods
- Adjust `MAX_GAS_PRICE`
- Batch more orders together

## Security

- **Never share your private key**
- Use a dedicated wallet for keeping
- Set reasonable gas limits
- Monitor for unusual activity

## Economics

### Revenue

- Keeper reward per execution (configurable)
- Higher traffic = more opportunities

### Costs

- Gas costs for transactions
- Infrastructure (RPC, server)

### Optimization

- Batch orders when possible
- Execute during low gas periods
- Monitor gas price trends
