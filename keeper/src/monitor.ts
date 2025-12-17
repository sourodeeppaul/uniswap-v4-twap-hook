/**
 * TWAP Keeper Monitor
 * Monitors system health and logs metrics
 */

import { TWAPExecutor } from "./executor";
import { KeeperConfig } from "./config";

export interface SystemMetrics {
    blockNumber: number;
    keeperBalance: string;
    pendingOrders: number;
    lastExecutionTime: number;
    successCount: number;
    failureCount: number;
    totalGasUsed: string;
}

export class KeeperMonitor {
    private executor: TWAPExecutor;
    private config: KeeperConfig;
    private metrics: SystemMetrics;

    constructor(executor: TWAPExecutor, config: KeeperConfig) {
        this.executor = executor;
        this.config = config;
        this.metrics = {
            blockNumber: 0,
            keeperBalance: "0",
            pendingOrders: 0,
            lastExecutionTime: 0,
            successCount: 0,
            failureCount: 0,
            totalGasUsed: "0",
        };
    }

    /**
     * Update system metrics
     */
    async updateMetrics(): Promise<void> {
        try {
            this.metrics.blockNumber = await this.executor.getBlockNumber();
            this.metrics.keeperBalance = (await this.executor.getBalance()).toString();

            const executableOrders = await this.executor.getExecutableOrders();
            this.metrics.pendingOrders = executableOrders.length;
        } catch (error) {
            console.error("Failed to update metrics:", error);
        }
    }

    /**
     * Record successful execution
     */
    recordSuccess(gasUsed: bigint): void {
        this.metrics.successCount++;
        this.metrics.lastExecutionTime = Date.now();
        this.metrics.totalGasUsed = (
            BigInt(this.metrics.totalGasUsed) + gasUsed
        ).toString();
    }

    /**
     * Record failed execution
     */
    recordFailure(): void {
        this.metrics.failureCount++;
    }

    /**
     * Get current metrics
     */
    getMetrics(): SystemMetrics {
        return { ...this.metrics };
    }

    /**
     * Log current status
     */
    logStatus(): void {
        console.log("\n========== KEEPER STATUS ==========");
        console.log(`Block: ${this.metrics.blockNumber}`);
        console.log(`Balance: ${this.metrics.keeperBalance} wei`);
        console.log(`Pending Orders: ${this.metrics.pendingOrders}`);
        console.log(`Success/Failure: ${this.metrics.successCount}/${this.metrics.failureCount}`);
        console.log(`Total Gas Used: ${this.metrics.totalGasUsed}`);
        console.log("====================================\n");
    }

    /**
     * Check if keeper has sufficient balance
     */
    async hasInsufficientBalance(minBalance: bigint): Promise<boolean> {
        const balance = await this.executor.getBalance();
        return balance < minBalance;
    }

    /**
     * Get success rate
     */
    getSuccessRate(): number {
        const total = this.metrics.successCount + this.metrics.failureCount;
        if (total === 0) return 0;
        return (this.metrics.successCount / total) * 100;
    }
}
