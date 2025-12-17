# Threat Model

## Assets

1. **User Funds**: Tokens deposited for TWAP orders
2. **Protocol Fees**: Accumulated protocol revenue
3. **System Integrity**: Correct order execution

## Threat Actors

### 1. Frontrunners/MEV Extractors

**Goal**: Extract value from pending orders

**Attack Vectors**:
- Monitor mempool for order creation
- Sandwich attacks during execution
- Oracle manipulation

**Mitigations**:
- Commit-reveal scheme
- TWAP validation (not spot price)
- Keeper execution (not user-initiated)

### 2. Malicious Keepers

**Goal**: Self-profit at expense of users

**Attack Vectors**:
- Execute at unfavorable prices
- Front-run their own executions
- DoS other keepers

**Mitigations**:
- Slippage protection per chunk
- TWAP deviation limits
- Multiple keeper support

### 3. Price Manipulators

**Goal**: Cause execution at manipulated prices

**Attack Vectors**:
- Flash loan attacks
- Multi-block manipulation
- Liquidity withdrawal

**Mitigations**:
- TWAP (not spot) for validation
- Pattern detection
- Pool-specific limits

### 4. Governance Attackers

**Goal**: Malicious parameter changes

**Attack Vectors**:
- Proposal with malicious changes
- Timelock bypass attempt
- Social engineering

**Mitigations**:
- Timelock delay (2-7 days)
- Multi-sig council for emergencies
- Bounded parameter ranges

### 5. Smart Contract Exploiters

**Goal**: Drain funds through vulnerabilities

**Attack Vectors**:
- Reentrancy
- Integer overflow
- Access control bypass
- Logic errors

**Mitigations**:
- ReentrancyGuard
- Solidity 0.8+ (built-in overflow checks)
- Comprehensive testing
- External audits

## Attack Scenarios

### Scenario 1: Sandwich Attack on Order Placement

1. Attacker monitors mempool
2. Sees order creation transaction
3. Front-runs with large buy
4. User order creates at worse price
5. Back-runs with sell

**Mitigation**: Commit-reveal prevents knowing order details

### Scenario 2: Oracle Manipulation

1. Attacker borrows large amount
2. Manipulates pool price
3. Keeper executes TWAP order at bad price
4. Attacker profits from price movement

**Mitigation**: TWAP window means manipulation must persist many blocks

### Scenario 3: Griefing Attack

1. Attacker creates many small orders
2. Consumes keeper gas
3. Real orders don't get executed

**Mitigation**: Rate limiting + minimum order size

## Risk Matrix

| Threat | Likelihood | Impact | Risk | Mitigation |
|--------|------------|--------|------|------------|
| Frontrunning | High | Medium | High | Commit-reveal |
| Oracle Manipulation | Medium | High | High | TWAP validation |
| Keeper Misbehavior | Low | Medium | Medium | Slippage limits |
| Smart Contract Bug | Low | Critical | High | Audits + testing |
| Governance Attack | Very Low | High | Medium | Timelock |

## Monitoring Requirements

1. **Price Deviation Alerts**: Trigger when spot differs from TWAP
2. **Volume Anomalies**: Unusual order creation patterns
3. **Execution Failures**: Track consecutive failures
4. **Gas Price Spikes**: May prevent execution
