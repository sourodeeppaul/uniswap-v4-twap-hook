/**
 * TWAP Hook Keeper Bot
 * Main entry point for the keeper service
 */

import * as dotenv from "dotenv";
import { loadConfig, validateConfig, KeeperConfig } from "./config";
import { TWAPExecutor, ExecutionResult } from "./executor";
import { KeeperMonitor } from "./monitor";

// Load environment variables
dotenv.config();

class TWAPKeeper {
    private config: KeeperConfig;
    private executor: TWAPExecutor;
    private monitor: KeeperMonitor;
    private isRunning: boolean = false;
    private pollInterval: NodeJS.Timeout | null = null;

    constructor() {
        this.config = loadConfig();
        validateConfig(this.config);
        this.executor = new TWAPExecutor(this.config);
        this.monitor = new KeeperMonitor(this.executor, this.config);
    }

    /**
     * Start the keeper bot
     */
    async start(): Promise<void> {
        console.log("Starting TWAP Keeper Bot...");
        console.log(`Chain ID: ${this.config.chainId}`);
        console.log(`Hook Address: ${this.config.hookAddress}`);
        console.log(`Poll Interval: ${this.config.pollIntervalMs}ms`);

        this.isRunning = true;

        // Initial metrics update
        await this.monitor.updateMetrics();
        this.monitor.logStatus();

        // Start polling loop
        this.pollInterval = setInterval(
            () => this.executionLoop(),
            this.config.pollIntervalMs
        );

        // Handle shutdown
        process.on("SIGINT", () => this.shutdown());
        process.on("SIGTERM", () => this.shutdown());

        console.log("Keeper bot started successfully!");
    }

    /**
     * Main execution loop
     */
    private async executionLoop(): Promise<void> {
        if (!this.isRunning) return;

        try {
            // Update metrics
            await this.monitor.updateMetrics();

            // Check balance
            const minBalance = BigInt(1e17); // 0.1 ETH
            if (await this.monitor.hasInsufficientBalance(minBalance)) {
                console.warn("Warning: Low keeper balance!");
            }

            // Get executable orders
            const orderIds = await this.executor.getExecutableOrders();

            if (orderIds.length === 0) {
                console.log(`[${new Date().toISOString()}] No orders ready for execution`);
                return;
            }

            console.log(`Found ${orderIds.length} orders ready for execution`);

            // Execute orders
            const results = await this.executeOrders(orderIds);

            // Process results
            for (const result of results) {
                if (result.success) {
                    console.log(`✓ Order ${result.orderId} executed: ${result.txHash}`);
                    this.monitor.recordSuccess(result.gasUsed || 0n);
                } else {
                    console.error(`✗ Order ${result.orderId} failed: ${result.error}`);
                    this.monitor.recordFailure();
                }
            }

            // Log status periodically
            if (results.length > 0) {
                this.monitor.logStatus();
            }
        } catch (error) {
            console.error("Execution loop error:", error);
        }
    }

    /**
     * Execute orders with retry logic
     */
    private async executeOrders(orderIds: string[]): Promise<ExecutionResult[]> {
        const results: ExecutionResult[] = [];

        // Use batch execution if multiple orders
        if (orderIds.length > 1 && orderIds.length <= this.config.maxOrdersPerBatch) {
            const batchResults = await this.executor.batchExecuteOrders(orderIds);
            return batchResults;
        }

        // Execute individually with retry
        for (const orderId of orderIds) {
            let result: ExecutionResult | null = null;

            for (let attempt = 1; attempt <= this.config.maxRetries; attempt++) {
                result = await this.executor.executeOrder(orderId);

                if (result.success) {
                    break;
                }

                console.log(
                    `Retry ${attempt}/${this.config.maxRetries} for order ${orderId}`
                );
                await this.sleep(this.config.retryDelayMs);
            }

            if (result) {
                results.push(result);
            }
        }

        return results;
    }

    /**
     * Graceful shutdown
     */
    private shutdown(): void {
        console.log("\nShutting down keeper bot...");
        this.isRunning = false;

        if (this.pollInterval) {
            clearInterval(this.pollInterval);
        }

        // Final status
        this.monitor.logStatus();
        console.log(`Success rate: ${this.monitor.getSuccessRate().toFixed(2)}%`);
        console.log("Goodbye!");

        process.exit(0);
    }

    /**
     * Sleep helper
     */
    private sleep(ms: number): Promise<void> {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}

// Main entry point
async function main(): Promise<void> {
    const keeper = new TWAPKeeper();
    await keeper.start();
}

main().catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
});
