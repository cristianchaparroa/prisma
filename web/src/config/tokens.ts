// Token configuration for the YieldMaximizer dashboard
export interface TokenConfig {
    address: string;
    symbol: string;
    decimals: number;
    name: string;
}

export const TOKENS: Record<string, TokenConfig> = {
    // Mainnet tokens from .env
    '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48': {
        address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        symbol: 'USDC',
        decimals: 6,
        name: 'USD Coin'
    },
    '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2': {
        address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 
        symbol: 'WETH',
        decimals: 18,
        name: 'Wrapped Ether'
    },
    '0x6B175474E89094C44Da98b954EedeAC495271d0F': {
        address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
        symbol: 'DAI',
        decimals: 18,
        name: 'Dai Stablecoin'
    },
    '0xdAC17F958D2ee523a2206206994597C13D831ec7': {
        address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        symbol: 'USDT',
        decimals: 6,
        name: 'Tether USD'
    },
    '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599': {
        address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
        symbol: 'WBTC',
        decimals: 8,
        name: 'Wrapped Bitcoin'
    }
};

// Helper function to get token info by address
export function getTokenInfo(address: string): TokenConfig | null {
    const normalizedAddress = address?.toLowerCase();
    const found = Object.values(TOKENS).find(token => 
        token.address.toLowerCase() === normalizedAddress
    );
    return found || null;
}

// Helper function to format token amount
export function formatTokenAmount(
    amount: bigint | number | string, 
    tokenAddress?: string, 
    showSymbol: boolean = true
): string {
    const token = tokenAddress ? getTokenInfo(tokenAddress) : null;
    const decimals = token?.decimals || 18;
    const symbol = token?.symbol || 'tokens';
    
    const numAmount = typeof amount === 'bigint' ? Number(amount) : Number(amount);
    const formattedAmount = numAmount / Math.pow(10, decimals);
    
    // Format based on token type with higher precision for tiny amounts
    let formatted: string;
    if (decimals === 6) { // USDC, USDT
        formatted = formattedAmount < 0.000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(6);
    } else if (decimals === 8) { // WBTC
        formatted = formattedAmount < 0.00000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(8);
    } else { // 18 decimals (ETH, DAI)
        formatted = formattedAmount < 0.000001 ? 
            formattedAmount.toExponential(3) : 
            formattedAmount.toFixed(6);
    }
    
    return showSymbol ? `${formatted} ${symbol}` : formatted;
}

// Default fallback for unknown tokens
export const DEFAULT_TOKEN: TokenConfig = {
    address: '',
    symbol: 'UNKNOWN',
    decimals: 18,
    name: 'Unknown Token'
};