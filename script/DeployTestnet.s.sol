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
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title DeployTestnet
/// @notice Simplified deployment for testnet with mock components
contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");

        console.log("Deploying TWAP Hook to Testnet");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with minimal configuration
        TWAPOrderVault vault = new TWAPOrderVault();
        console.log("Vault:", address(vault));

        TWAPOracle oracle = new TWAPOracle(poolManager, 50, 5);
        console.log("Oracle:", address(oracle));

        CircuitBreaker circuitBreaker = new CircuitBreaker(1000, 20, 10, 300);
        console.log("Circuit Breaker:", address(circuitBreaker));

        CommitReveal commitReveal = new CommitReveal(1, 50, false);
        console.log("Commit-Reveal:", address(commitReveal));

        RateLimiter rateLimiter = new RateLimiter(10000e18, 600, 60);
        console.log("Rate Limiter:", address(rateLimiter));

        TWAPExecutor executor = new TWAPExecutor(
            poolManager,
            address(vault),
            address(oracle),
            address(circuitBreaker),
            1000000,
            50
        );
        console.log("Executor:", address(executor));

        TWAPHook hook = new TWAPHook(
            IPoolManager(poolManager),
            address(vault),
            address(executor),
            address(oracle),
            address(circuitBreaker),
            address(commitReveal),
            address(rateLimiter)
        );
        console.log("Hook:", address(hook));

        // Configure
        vault.setHook(address(hook));
        vault.setExecutor(address(executor));
        executor.setHook(address(hook));

        vm.stopBroadcast();

        console.log("\nTestnet deployment complete!");
    }
}
