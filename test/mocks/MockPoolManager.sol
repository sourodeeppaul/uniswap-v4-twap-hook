// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title MockPoolManager
/// @notice Simplified mock of Uniswap v4 Pool Manager for testing
contract MockPoolManager {
    using PoolIdLibrary for PoolKey;

    // ============ State ============

    struct PoolState {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
        uint128 liquidity;
    }

    mapping(PoolId => PoolState) public pools;
    mapping(PoolId => bool) public initialized;

    // ============ Mock Setters ============

    function setPoolState(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        uint128 liquidity
    ) external {
        PoolId poolId = key.toId();
        pools[poolId] = PoolState({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            protocolFee: 0,
            lpFee: 3000,
            liquidity: liquidity
        });
        initialized[poolId] = true;
    }

    function setSqrtPriceX96(PoolKey calldata key, uint160 sqrtPriceX96) external {
        PoolId poolId = key.toId();
        pools[poolId].sqrtPriceX96 = sqrtPriceX96;
    }

    function setLiquidity(PoolKey calldata key, uint128 liquidity) external {
        PoolId poolId = key.toId();
        pools[poolId].liquidity = liquidity;
    }

    // ============ IPoolManager Interface (Partial) ============

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        PoolState storage state = pools[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return pools[poolId].liquidity;
    }

    function isInitialized(PoolId poolId) external view returns (bool) {
        return initialized[poolId];
    }

    /// @notice Mock swap function
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta delta) {
        // Simplified mock - returns a predictable delta based on input
        int256 amount = params.amountSpecified;
        
        if (params.zeroForOne) {
            // token0 -> token1
            if (amount < 0) {
                // Exact input
                int128 amount0 = int128(amount);
                int128 amount1 = int128(-amount); // Same amount out (1:1 for simplicity)
                delta = toBalanceDelta(amount0, amount1);
            }
        } else {
            // token1 -> token0
            if (amount < 0) {
                int128 amount1 = int128(amount);
                int128 amount0 = int128(-amount);
                delta = toBalanceDelta(amount0, amount1);
            }
        }
    }

    /// @notice Mock initialize
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        pools[poolId] = PoolState({
            sqrtPriceX96: sqrtPriceX96,
            tick: 0,
            protocolFee: 0,
            lpFee: 3000,
            liquidity: 1e18
        });
        initialized[poolId] = true;
        return 0;
    }

    // ============ Helpers ============

    function toBalanceDelta(int128 amount0, int128 amount1) internal pure returns (BalanceDelta) {
        // Pack two int128 values into a single bytes32/int256
        return BalanceDelta.wrap(
            int256(uint256(uint128(amount0)) << 128) | int256(uint256(uint128(amount1)))
        );
    }
}
