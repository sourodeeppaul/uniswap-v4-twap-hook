/**
 * TWAP Hook Keeper Configuration
 */

export interface KeeperConfig {
  // RPC Configuration
  rpcUrl: string;
  chainId: number;

  // Contract Addresses
  hookAddress: string;
  executorAddress: string;

  // Keeper Settings
  privateKey: string;
  maxGasPrice: bigint;
  gasLimit: number;

  // Execution Settings
  pollIntervalMs: number;
  maxOrdersPerBatch: number;
  minProfitThreshold: bigint;

  // Retry Settings
  maxRetries: number;
  retryDelayMs: number;

  // Monitoring
  enableMetrics: boolean;
  metricsPort: number;
}

export function loadConfig(): KeeperConfig {
  return {
    // RPC
    rpcUrl: process.env.RPC_URL || "http://localhost:8545",
    chainId: parseInt(process.env.CHAIN_ID || "1"),

    // Contracts
    hookAddress: process.env.HOOK_ADDRESS || "",
    executorAddress: process.env.EXECUTOR_ADDRESS || "",

    // Keeper
    privateKey: process.env.KEEPER_PRIVATE_KEY || "",
    maxGasPrice: BigInt(process.env.MAX_GAS_PRICE || "100000000000"), // 100 gwei
    gasLimit: parseInt(process.env.GAS_LIMIT || "500000"),

    // Execution
    pollIntervalMs: parseInt(process.env.POLL_INTERVAL_MS || "12000"), // ~1 block
    maxOrdersPerBatch: parseInt(process.env.MAX_ORDERS_PER_BATCH || "10"),
    minProfitThreshold: BigInt(process.env.MIN_PROFIT_THRESHOLD || "0"),

    // Retry
    maxRetries: parseInt(process.env.MAX_RETRIES || "3"),
    retryDelayMs: parseInt(process.env.RETRY_DELAY_MS || "1000"),

    // Monitoring
    enableMetrics: process.env.ENABLE_METRICS === "true",
    metricsPort: parseInt(process.env.METRICS_PORT || "9090"),
  };
}

export function validateConfig(config: KeeperConfig): void {
  if (!config.rpcUrl) {
    throw new Error("RPC_URL is required");
  }
  if (!config.hookAddress) {
    throw new Error("HOOK_ADDRESS is required");
  }
  if (!config.executorAddress) {
    throw new Error("EXECUTOR_ADDRESS is required");
  }
  if (!config.privateKey) {
    throw new Error("KEEPER_PRIVATE_KEY is required");
  }
}
