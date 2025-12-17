# TWAP Hook Keeper Bot

Off-chain keeper service for executing TWAP orders.

## Overview

The keeper bot monitors the TWAP Hook contract for orders ready to be executed and submits transactions to execute them. It handles:

- Polling for executable orders
- Gas price management
- Batch execution
- Retry logic
- Metrics and monitoring

## Setup

### Prerequisites

- Node.js >= 18.0.0
- npm or yarn
- Funded Ethereum wallet for gas

### Installation

```bash
cd keeper
npm install
```

### Configuration

Create a `.env` file:

```bash
# Required
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
CHAIN_ID=1
HOOK_ADDRESS=0x...
EXECUTOR_ADDRESS=0x...
KEEPER_PRIVATE_KEY=0x...

# Optional
MAX_GAS_PRICE=100000000000
GAS_LIMIT=500000
POLL_INTERVAL_MS=12000
MAX_ORDERS_PER_BATCH=10
MAX_RETRIES=3
```

### Running

Development:
```bash
npm run dev
```

Production:
```bash
npm run build
npm start
```

## Architecture

```
keeper/
├── src/
│   ├── index.ts      # Main entry point
│   ├── executor.ts   # Order execution logic
│   ├── monitor.ts    # Health monitoring
│   └── config.ts     # Configuration
└── package.json
```

## Monitoring

The keeper logs:
- Executable order count
- Execution success/failure
- Gas usage
- Keeper balance

## Security

- Never commit your private key
- Use a dedicated keeper wallet
- Set reasonable gas limits
- Monitor balance regularly

## Troubleshooting

**No orders found**: Check that orders exist and are past their interval
**Transaction failures**: Check gas price and slippage settings
**High gas**: Adjust MAX_GAS_PRICE or wait for lower gas
