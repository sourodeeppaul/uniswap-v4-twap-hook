# Uniswap v4 TWAP Hook

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue.svg)](https://docs.soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://book.getfoundry.sh/)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-FF007A.svg)](https://uniswap.org/)
[![Tests](https://img.shields.io/badge/Tests-53%20Passing-brightgreen.svg)]()

A sophisticated Time-Weighted Average Price (TWAP) Hook for Uniswap v4 that enables users to execute large orders by splitting them into smaller chunks over time, minimizing price impact and slippage.

## Overview

Instead of executing a large swap at once (causing high slippage), users deposit tokens into the TWAP Hook. The hook automatically splits the order into chunks and executes them at regular block intervals.

### Key Features

- **Order Splitting**: Divide large orders into configurable chunks
- **Scheduled Execution**: Execute chunks every N blocks automatically
- **MEV Protection**: Commit-reveal scheme prevents frontrunning
- **Price Guards**: TWAP validation prevents manipulation
- **Circuit Breaker**: Emergency stop mechanism
- **Governance**: Timelock-controlled parameter updates

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       User Interface                        │
├─────────────────────────────────────────────────────────────┤
│  1. Commit order hash  →  CommitReveal                      │
│  2. Reveal & deposit   →  TWAPHook  →  TWAPOrderVault       │
├─────────────────────────────────────────────────────────────┤
│                    Execution Layer                          │
│  Keeper Bot  →  TWAPExecutor  →  PoolManager                │
├─────────────────────────────────────────────────────────────┤
│                    Security Layer                           │
│  CircuitBreaker │ PriceGuard │ RateLimiter │ TWAPOracle     │
├─────────────────────────────────────────────────────────────┤
│                    Governance                               │
│  TWAPGovernor  →  Timelock  →  Parameter Updates            │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18 (for keeper)

### Installation

```bash
# Clone repository
git clone https://github.com/sourodeeppaul/uniswap-v4-twap-hook
cd uniswap-v4-twap-hook

# Install Foundry dependencies
forge install

# Install keeper dependencies
cd keeper && npm install && cd ..
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/TWAPOrderVault.t.sol
```

### Deploy

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# Then deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Usage

### Creating a TWAP Order

```solidity
// 1. Approve tokens
token.approve(address(hook), amount);

// 2. Create order parameters
TWAPTypes.OrderParams memory params = TWAPTypes.OrderParams({
    poolKey: poolKey,
    zeroForOne: true,
    amountIn: 10 ether,
    minAmountOut: 9.5 ether,
    numChunks: 10,
    intervalBlocks: 5,
    maxSlippageBps: 100,
    deadline: block.timestamp + 1 days,
    recipient: msg.sender
});

// 3. Create order
bytes32 orderId = hook.createOrder(params);
```

### Cancelling an Order

```solidity
hook.cancelOrder(orderId);
```

## Project Structure

```
uniswap-v4-twap-hook/
├── src/
│   ├── TWAPHook.sol              # Main hook contract
│   ├── TWAPOrderVault.sol        # Order storage & custody
│   ├── TWAPExecutor.sol          # Execution logic
│   ├── TWAPOracle.sol            # Price oracle
│   ├── security/                 # Security modules
│   ├── governance/               # Governance contracts
│   ├── libraries/                # Helper libraries
│   ├── interfaces/               # Contract interfaces
│   └── types/                    # Type definitions
├── test/                         # Test suite
├── script/                       # Deployment scripts
├── keeper/                       # Off-chain keeper bot
└── docs/                         # Documentation
```

## Configuration

Default configuration in `TWAPHook`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| minChunkSize | 0.001 ETH | Minimum chunk size |
| maxChunkSize | 1M tokens | Maximum chunk size |
| minIntervalBlocks | 1 | Minimum blocks between executions |
| maxIntervalBlocks | 1000 | Maximum blocks between executions |
| maxOrderDuration | 50000 blocks | Maximum order lifetime |
| maxSlippageBps | 500 (5%) | Maximum allowed slippage |

## Security

### Audits

This project has not been audited. Use at your own risk.

### Security Features

- **Commit-Reveal**: Prevents frontrunning of order placement
- **Circuit Breaker**: Emergency stop with guardian access
- **Rate Limiting**: Prevents abuse and DoS attacks
- **Price Guards**: TWAP validation for manipulation protection
- **Timelock**: Governance actions require delay

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Security](docs/SECURITY.md)
- [Threat Model](docs/THREAT_MODEL.md)
- [Integration Guide](docs/INTEGRATION.md)
- [Keeper Guide](docs/KEEPER_GUIDE.md)
- [Gas Benchmarks](docs/GAS_BENCHMARKS.md)

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE)

## Disclaimer

This software is provided "as is", without warranty of any kind. Use at your own risk. Always test thoroughly on testnet before mainnet deployment.
