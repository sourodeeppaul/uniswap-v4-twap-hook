# Security

## Security Model

### Trust Assumptions

1. **Pool Manager**: Uniswap v4 Pool Manager is trusted and correctly implemented
2. **Oracles**: Price data from pools is accurate within normal market conditions
3. **Keepers**: Keepers are untrusted but economically incentivized
4. **Governance**: Timelock provides delay for parameter changes

### Access Control

| Role | Permissions |
|------|-------------|
| Owner | Configure components, update parameters (via timelock) |
| Guardian | Trigger circuit breaker |
| Keeper | Execute orders, earn rewards |
| User | Create/cancel own orders |

## Security Features

### 1. MEV Protection (CommitReveal)

**Problem**: Frontrunners can see pending orders and extract value.

**Solution**: Two-phase order creation:
1. Commit: Submit hash of order parameters
2. Reveal: After delay, reveal actual parameters

**Parameters**:
- `commitRevealDelay`: Blocks between commit and reveal
- `commitmentExpiry`: Maximum blocks before commitment expires

### 2. Circuit Breaker

**Problem**: System failures or attacks could cause losses.

**Solution**: Emergency stop mechanism:
- Guardians can pause immediately
- Auto-trigger on consecutive failures
- Cooldown period after reset

**Parameters**:
- `maxConsecutiveFailures`: Failures before auto-trigger
- `cooldownPeriod`: Seconds before normal operation resumes

### 3. Rate Limiting

**Problem**: Attackers could spam orders to DoS the system.

**Solution**: Per-user and global rate limits:
- Daily volume limits per user
- Pool-wide volume limits
- Cooldown after hitting limits

### 4. Price Guards

**Problem**: Price manipulation could cause unfavorable execution.

**Solution**: TWAP-based validation:
- Compare spot price to TWAP
- Reject execution if deviation too high
- Pattern detection for sandwich attacks

## Known Limitations

1. **Oracle Lag**: TWAP reflects historical prices, not current
2. **Execution Timing**: Depends on keeper activity
3. **Partial Fills**: Orders may expire partially filled
4. **Gas Costs**: High gas prices may make execution unprofitable

## Security Checklist

- [ ] All external calls checked for reentrancy
- [ ] Integer overflow/underflow prevented (Solidity 0.8+)
- [ ] Access control on privileged functions
- [ ] Emergency pause functionality
- [ ] Rate limiting in place
- [ ] Price validation before execution
- [ ] Timelock on parameter changes

## Incident Response

1. **Detection**: Monitor for anomalies
2. **Triage**: Assess severity
3. **Mitigation**: Trigger circuit breaker if needed
4. **Communication**: Notify users
5. **Resolution**: Deploy fix through governance
6. **Post-mortem**: Document and improve
