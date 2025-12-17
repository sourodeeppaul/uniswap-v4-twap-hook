// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TWAPHook} from "../src/TWAPHook.sol";
import {TWAPOrderVault} from "../src/TWAPOrderVault.sol";
import {TWAPExecutor} from "../src/TWAPExecutor.sol";
import {TWAPOracle} from "../src/TWAPOracle.sol";
import {CircuitBreaker} from "../src/security/CircuitBreaker.sol";
import {CommitReveal} from "../src/security/CommitReveal.sol";
import {RateLimiter} from "../src/security/RateLimiter.sol";
import {PriceGuard} from "../src/security/PriceGuard.sol";
import {Timelock} from "../src/governance/Timelock.sol";
import {TWAPGovernor} from "../src/governance/TWAPGovernor.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @title Deploy
/// @notice Production deployment script for TWAP Hook system
contract Deploy is Script {
    // ============ Configuration ============

    // Pool Manager address (set for target chain)
    address public poolManager;

    // Deployment addresses
    TWAPOrderVault public vault;
    TWAPExecutor public executor;
    TWAPOracle public oracle;
    CircuitBreaker public circuitBreaker;
    CommitReveal public commitReveal;
    RateLimiter public rateLimiter;
    PriceGuard public priceGuard;
    Timelock public timelock;
    TWAPGovernor public governor;
    TWAPHook public hook;

    // Deploy parameters
    uint32 constant TWAP_WINDOW = 100;
    uint32 constant MIN_OBSERVATIONS = 10;
    uint256 constant MAX_GAS_PER_EXECUTION = 500000;
    uint16 constant KEEPER_REWARD_BPS = 10;
    uint16 constant PRICE_DEVIATION_THRESHOLD = 500;
    uint256 constant VOLUME_SPIKE_THRESHOLD = 10;
    uint32 constant MAX_CONSECUTIVE_FAILURES = 5;
    uint256 constant COOLDOWN_PERIOD = 3600;
    uint32 constant COMMIT_REVEAL_DELAY = 2;
    uint32 constant COMMITMENT_EXPIRY = 100;
    uint256 constant RATE_LIMIT_AMOUNT = 1000e18;
    uint256 constant RATE_LIMIT_WINDOW = 3600;
    uint256 constant RATE_LIMIT_COOLDOWN = 600;
    uint256 constant TIMELOCK_DELAY = 2 days;

    function run() external {
        // Get deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get pool manager from env
        poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");

        console.log("Deploying TWAP Hook System");
        console.log("Deployer:", deployer);
        console.log("Pool Manager:", poolManager);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Vault
        vault = new TWAPOrderVault();
        console.log("Vault deployed:", address(vault));

        // 2. Deploy Oracle
        oracle = new TWAPOracle(poolManager, TWAP_WINDOW, MIN_OBSERVATIONS);
        console.log("Oracle deployed:", address(oracle));

        // 3. Deploy Circuit Breaker
        circuitBreaker = new CircuitBreaker(
            PRICE_DEVIATION_THRESHOLD,
            VOLUME_SPIKE_THRESHOLD,
            MAX_CONSECUTIVE_FAILURES,
            COOLDOWN_PERIOD
        );
        console.log("Circuit Breaker deployed:", address(circuitBreaker));

        // 4. Deploy Commit-Reveal
        commitReveal = new CommitReveal(COMMIT_REVEAL_DELAY, COMMITMENT_EXPIRY, true);
        console.log("Commit-Reveal deployed:", address(commitReveal));

        // 5. Deploy Rate Limiter
        rateLimiter = new RateLimiter(RATE_LIMIT_AMOUNT, RATE_LIMIT_WINDOW, RATE_LIMIT_COOLDOWN);
        console.log("Rate Limiter deployed:", address(rateLimiter));

        // 6. Deploy Executor
        executor = new TWAPExecutor(
            poolManager,
            address(vault),
            address(oracle),
            address(circuitBreaker),
            MAX_GAS_PER_EXECUTION,
            KEEPER_REWARD_BPS
        );
        console.log("Executor deployed:", address(executor));

        // 7. Deploy Price Guard
        priceGuard = new PriceGuard(
            address(oracle),
            PRICE_DEVIATION_THRESHOLD,
            TWAP_WINDOW,
            50
        );
        console.log("Price Guard deployed:", address(priceGuard));

        // 8. Deploy Hook (requires address mining for permissions)
        // Note: In production, use HookMiner to find correct salt
        hook = new TWAPHook(
            IPoolManager(poolManager),
            address(vault),
            address(executor),
            address(oracle),
            address(circuitBreaker),
            address(commitReveal),
            address(rateLimiter)
        );
        console.log("Hook deployed:", address(hook));

        // 9. Configure component authorizations
        vault.setHook(address(hook));
        vault.setExecutor(address(executor));
        executor.setHook(address(hook));
        console.log("Component authorizations configured");

        // 10. Deploy Governance (optional)
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;

        timelock = new Timelock(TIMELOCK_DELAY, proposers, executors, deployer);
        console.log("Timelock deployed:", address(timelock));

        address[] memory initialCouncil = new address[](1);
        initialCouncil[0] = deployer;

        governor = new TWAPGovernor(address(hook), address(timelock), initialCouncil, 1);
        console.log("Governor deployed:", address(governor));

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _logDeploymentSummary() internal view {
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Pool Manager:", poolManager);
        console.log("Vault:", address(vault));
        console.log("Executor:", address(executor));
        console.log("Oracle:", address(oracle));
        console.log("Circuit Breaker:", address(circuitBreaker));
        console.log("Commit-Reveal:", address(commitReveal));
        console.log("Rate Limiter:", address(rateLimiter));
        console.log("Price Guard:", address(priceGuard));
        console.log("Hook:", address(hook));
        console.log("Timelock:", address(timelock));
        console.log("Governor:", address(governor));
        console.log("==========================================\n");
    }
}
