// Dynamic Pool configuration for YieldMaximizer dashboard
import { TOKENS, getTokenInfo } from './tokens';

export interface PoolConfig {
    poolId: string;
    token0: {
        address: string;
        symbol: string;
        decimals: number;
    };
    token1: {
        address: string;
        symbol: string;
        decimals: number;
    };
    fee?: number;
    description: string;
    discoveredAt: Date;
}

// Dynamic pool registry - populated as pools are discovered
export const POOL_CONFIGS: Record<string, PoolConfig> = {};

// Static fallback for known token pairs (when pool ID is not yet discovered)
export const KNOWN_TOKEN_PAIRS: Array<{
    token0: string;
    token1: string;
    symbol0: string;
    symbol1: string;
    description: string;
}> = [
    {
        token0: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI
        token1: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
        symbol0: 'DAI',
        symbol1: 'USDC',
        description: 'DAI/USDC'
    },
    {
        token0: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
        token1: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
        symbol0: 'WETH',
        symbol1: 'USDC', 
        description: 'WETH/USDC'
    }
];

// Dynamic pool discovery - registers a pool when first encountered
export function discoverPool(poolId: string, token0Address: string, token1Address: string, fee?: number): PoolConfig {
    // Check if pool already exists
    if (POOL_CONFIGS[poolId]) {
        return POOL_CONFIGS[poolId];
    }

    // Get token info for both tokens
    const token0Info = getTokenInfo(token0Address);
    const token1Info = getTokenInfo(token1Address);

    // Create pool config
    const poolConfig: PoolConfig = {
        poolId,
        token0: {
            address: token0Address,
            symbol: token0Info?.symbol || 'UNK0',
            decimals: token0Info?.decimals || 18
        },
        token1: {
            address: token1Address,
            symbol: token1Info?.symbol || 'UNK1', 
            decimals: token1Info?.decimals || 18
        },
        fee,
        description: `${token0Info?.symbol || 'UNK0'}/${token1Info?.symbol || 'UNK1'}${fee ? ` ${fee/10000}%` : ''}`,
        discoveredAt: new Date()
    };

    // Register the pool
    POOL_CONFIGS[poolId] = poolConfig;
    
    console.log(`🔍 Pool discovered: ${poolConfig.description}`);

    return poolConfig;
}

// Helper function to get pool configuration (with fallback discovery)
export function getPoolConfig(poolId: string): PoolConfig | null {
    return POOL_CONFIGS[poolId] || null;
}

// Discover pool from FeesCollected event
export function discoverPoolFromEvent(poolId: string, tokenAddress: string, isToken0: boolean): PoolConfig | null {
    // If we already know this pool, return it
    if (POOL_CONFIGS[poolId]) {
        return POOL_CONFIGS[poolId];
    }

    // Try to infer the other token from known pairs
    const knownPair = KNOWN_TOKEN_PAIRS.find(pair => 
        (isToken0 && pair.token0.toLowerCase() === tokenAddress.toLowerCase()) ||
        (!isToken0 && pair.token1.toLowerCase() === tokenAddress.toLowerCase())
    );

    if (knownPair) {
        return discoverPool(
            poolId,
            knownPair.token0,
            knownPair.token1
        );
    }

    // Partial discovery - skip logging for cleaner console

    return null;
}

// Discover pool when we have both tokens from multiple events
export function discoverPoolFromTokens(poolId: string, token0Address: string, token1Address: string): PoolConfig | null {
    // If we already know this pool, return it
    if (POOL_CONFIGS[poolId]) {
        return POOL_CONFIGS[poolId];
    }

    // Create the pool config with both tokens
    return discoverPool(poolId, token0Address, token1Address);
}

// Helper function to get token info within a pool
export function getTokenInPool(poolId: string, isToken0: boolean) {
    const pool = getPoolConfig(poolId);
    if (!pool) return null;
    
    return isToken0 ? pool.token0 : pool.token1;
}

// Helper function to format amount with correct token
export function formatPoolTokenAmount(amount: bigint | number, poolId: string, isToken0: boolean): string {
    const token = getTokenInPool(poolId, isToken0);
    if (!token) {
        // Fallback to generic formatting
        const numAmount = typeof amount === 'bigint' ? Number(amount) : amount;
        return `${numAmount} tokens`;
    }
    
    const numAmount = typeof amount === 'bigint' ? Number(amount) : amount;
    const formattedAmount = numAmount / Math.pow(10, token.decimals);
    
    // Format based on token decimals with higher precision for tiny amounts
    let formatted: string;
    if (token.decimals === 6) { // USDC
        formatted = formattedAmount < 0.000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(6);
    } else if (token.decimals === 18) { // DAI
        formatted = formattedAmount < 0.000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(6);
    } else {
        formatted = formattedAmount < 0.00000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(8);
    }
    
    return `${formatted} ${token.symbol}`;
}

// Get pool description for display
export function getPoolDescription(poolId: string): string {
    const pool = getPoolConfig(poolId);
    return pool ? pool.description : `Pool ${poolId.slice(0, 8)}...`;
}