/**
 * TWAP Order Executor
 * Handles execution of ready TWAP orders
 */

import { ethers, Contract, Wallet, Provider } from "ethers";
import { KeeperConfig } from "./config";

// ABI fragments for the contracts we need
const HOOK_ABI = [
    "function getExecutableOrders(uint256 maxOrders) view returns (bytes32[])",
    "function executeOrder(bytes32 orderId) returns (uint8)",
    "function batchExecuteOrders(bytes32[] orderIds) returns (uint8[])",
    "function canExecuteOrder(bytes32 orderId) view returns (bool, string)",
    "function getOrder(bytes32 orderId) view returns (tuple(bytes32 id, address owner, tuple(tuple(address,address,uint24,int24,address) poolKey, bool zeroForOne, uint256 amountIn, uint256 minAmountOut, uint32 numChunks, uint32 intervalBlocks, uint16 maxSlippageBps, uint256 deadline, address recipient) params, uint8 status, tuple(uint32 chunksExecuted, uint256 amountInRemaining, uint256 amountOutAccumulated, uint256 lastExecutionBlock, uint256 averagePrice, uint256 totalGasUsed) executionState, uint256 createdAt, uint256 updatedAt))",
];

const EXECUTOR_ABI = [
    "function executeChunk(bytes32 orderId) returns (uint8, uint256)",
    "function canExecute(bytes32 orderId) view returns (bool, uint256)",
    "function simulateExecution(bytes32 orderId) view returns (uint256, uint256)",
];

export interface ExecutionResult {
    orderId: string;
    success: boolean;
    txHash?: string;
    gasUsed?: bigint;
    error?: string;
}

export class TWAPExecutor {
    private provider: Provider;
    private wallet: Wallet;
    private hookContract: Contract;
    private executorContract: Contract;
    private config: KeeperConfig;

    constructor(config: KeeperConfig) {
        this.config = config;
        this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
        this.wallet = new ethers.Wallet(config.privateKey, this.provider);
        this.hookContract = new ethers.Contract(
            config.hookAddress,
            HOOK_ABI,
            this.wallet
        );
        this.executorContract = new ethers.Contract(
            config.executorAddress,
            EXECUTOR_ABI,
            this.wallet
        );
    }

    /**
     * Get all orders ready for execution
     */
    async getExecutableOrders(): Promise<string[]> {
        try {
            const orders = await this.hookContract.getExecutableOrders(
                this.config.maxOrdersPerBatch
            );
            return orders;
        } catch (error) {
            console.error("Failed to get executable orders:", error);
            return [];
        }
    }

    /**
     * Check if a specific order can be executed
     */
    async canExecuteOrder(
        orderId: string
    ): Promise<{ canExecute: boolean; reason: string }> {
        try {
            const [canExec, reason] = await this.hookContract.canExecuteOrder(
                orderId
            );
            return { canExecute: canExec, reason };
        } catch (error) {
            return { canExecute: false, reason: String(error) };
        }
    }

    /**
     * Simulate execution to estimate output
     */
    async simulateExecution(
        orderId: string
    ): Promise<{ expectedOut: bigint; priceImpact: bigint }> {
        try {
            const [expectedOut, priceImpact] =
                await this.executorContract.simulateExecution(orderId);
            return { expectedOut, priceImpact };
        } catch (error) {
            console.error("Simulation failed:", error);
            return { expectedOut: 0n, priceImpact: 0n };
        }
    }

    /**
     * Execute a single order
     */
    async executeOrder(orderId: string): Promise<ExecutionResult> {
        try {
            // Check if profitable (optional)
            const simulation = await this.simulateExecution(orderId);
            console.log(
                `Order ${orderId}: Expected output ${simulation.expectedOut}, Impact ${simulation.priceImpact} bps`
            );

            // Check gas price
            const feeData = await this.provider.getFeeData();
            if (feeData.gasPrice && feeData.gasPrice > this.config.maxGasPrice) {
                return {
                    orderId,
                    success: false,
                    error: `Gas price too high: ${feeData.gasPrice}`,
                };
            }

            // Execute
            const tx = await this.hookContract.executeOrder(orderId, {
                gasLimit: this.config.gasLimit,
            });

            console.log(`Transaction sent: ${tx.hash}`);

            const receipt = await tx.wait();

            return {
                orderId,
                success: receipt.status === 1,
                txHash: receipt.hash,
                gasUsed: receipt.gasUsed,
            };
        } catch (error) {
            return {
                orderId,
                success: false,
                error: String(error),
            };
        }
    }

    /**
     * Batch execute multiple orders
     */
    async batchExecuteOrders(orderIds: string[]): Promise<ExecutionResult[]> {
        if (orderIds.length === 0) {
            return [];
        }

        try {
            // Check gas price
            const feeData = await this.provider.getFeeData();
            if (feeData.gasPrice && feeData.gasPrice > this.config.maxGasPrice) {
                return orderIds.map((id) => ({
                    orderId: id,
                    success: false,
                    error: `Gas price too high: ${feeData.gasPrice}`,
                }));
            }

            // Execute batch
            const tx = await this.hookContract.batchExecuteOrders(orderIds, {
                gasLimit: this.config.gasLimit * orderIds.length,
            });

            console.log(`Batch transaction sent: ${tx.hash}`);

            const receipt = await tx.wait();

            return orderIds.map((id) => ({
                orderId: id,
                success: receipt.status === 1,
                txHash: receipt.hash,
                gasUsed: receipt.gasUsed / BigInt(orderIds.length),
            }));
        } catch (error) {
            return orderIds.map((id) => ({
                orderId: id,
                success: false,
                error: String(error),
            }));
        }
    }

    /**
     * Get keeper wallet balance
     */
    async getBalance(): Promise<bigint> {
        return await this.provider.getBalance(this.wallet.address);
    }

    /**
     * Get current block number
     */
    async getBlockNumber(): Promise<number> {
        return await this.provider.getBlockNumber();
    }
}
