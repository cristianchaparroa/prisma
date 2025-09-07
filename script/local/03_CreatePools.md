# Create Hook-Enabled Liquidity Pools Script

## Overview
Creates 5 Uniswap V4 liquidity pools with the YieldMaximizerHook integrated from the start, enabling automatic yield maximization across different token pairs and fee tiers.

## Prerequisites

1. **Infrastructure, tokens, and hook deployed**:
```bash
# Should be done via run-local-env.sh or manually:
./scripts/local/run-local-env.sh  # Deploys everything automatically
```

2. **Environment properly set**:
```bash
source .env  # Should contain all addresses
```

3. **Required environment variables**:
```bash
# Infrastructure
POOL_MANAGER=0x...
HOOK_ADDRESS=0x...  # YieldMaximizerHook

# Token addresses  
TOKEN_WETH=0x...
TOKEN_USDC=0x...
TOKEN_DAI=0x...
TOKEN_WBTC=0x...
TOKEN_YIELD=0x...
```

## Execute Pool Creation

```bash
forge script script/local/03_CreatePools.s.sol:CreatePools \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v
```

## Pools Created

| Pool | Tokens | Fee Tier | Tick Spacing | Initial Price | Purpose |
|------|--------|----------|--------------|---------------|---------|
| **WETH/USDC** | ETH/Stable | 0.3% | 60 | 1 WETH = 2500 USDC | High volume pair |
| **WETH/DAI** | ETH/Stable | 0.3% | 60 | 1 WETH = 2500 DAI | Alternative stable |
| **WBTC/WETH** | Crypto/Crypto | 0.3% | 60 | 1 WBTC = 20 WETH | Volatile pair |
| **USDC/DAI** | Stable/Stable | 0.05% | 10 | 1 USDC = 1 DAI | Low volatility |
| **YIELD/WETH** | Token/ETH | 1.0% | 200 | 100 YIELD = 1 WETH | Protocol token |

## Expected Output

```
== Logs ==
  Creating Uniswap V4 liquidity pools...
  Loading contracts from environment variables...
  PoolManager loaded: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  Tokens loaded:
    WETH: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
    USDC: 0x0165878A594ca255338adfa4d48449f69242Eb8F
    ...

  Creating pool: WETH/USDC
    Currency0: 0x0165878A594ca255338adfa4d48449f69242Eb8F
    Currency1: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
    Fee: 3000
    Tick Spacing: 60
    Hook: 0x429051c72d815C038aE8D6442dAe87DD6d255540
  Hook-enabled pool created with ID: 0x1234...
    Hook address in pool: 0x429051c72d815C038aE8D6442dAe87DD6d255540

  Creating pool: WETH/DAI
    ...

=== POOL CREATION COMPLETE ===
  Total pools created: 5

  Pool info saved to: ./deployments/pools.env
```

## Generated Files

- **`deployments/pools.env`**: Pool IDs and configuration details
- **Pool state**: All pools initialized and ready for liquidity

## Pool Design Strategy

### Fee Tier Selection

**0.05% (USDC/DAI)**
- Stable-to-stable pairs with minimal price movement
- Encourages high-frequency arbitrage
- Low slippage for large trades

**0.3% (WETH/USDC, WETH/DAI, WBTC/WETH)**
- Standard fee for most crypto pairs
- Balance between LP rewards and trader costs
- Most common fee tier in DeFi

**1.0% (YIELD/WETH)**
- Higher fee for volatile/exotic pairs
- Compensates LPs for increased impermanent loss risk
- Protocol token pricing discovery

### Tick Spacing Logic

**Tick Spacing 10** (0.05% fee)
- Fine-grained price precision for stable pairs
- Minimal slippage between ticks

**Tick Spacing 60** (0.3% fee)
- Standard precision for most pairs
- Good balance of gas efficiency and precision

**Tick Spacing 200** (1.0% fee)
- Wider price gaps for volatile pairs
- More gas-efficient for larger price movements

## Price Initialization

### Realistic Price Setting
```solidity
// WETH/USDC: 1 WETH = 2500 USDC (realistic ETH price)
sqrtPriceX96 = _calculateSqrtPriceX96(2500, 1)

// WBTC/WETH: 1 WBTC = 20 WETH (≈$50k BTC price)
sqrtPriceX96 = _calculateSqrtPriceX96(20, 1)

// USDC/DAI: 1 USDC = 1 DAI (stable peg)
sqrtPriceX96 = _calculateSqrtPriceX96(1, 1)

// YIELD/WETH: 100 YIELD = 1 WETH (governance token)
sqrtPriceX96 = _calculateSqrtPriceX96(100, 1)
```

### Currency Sorting
```solidity
struct CurrencyPair {
    Currency currency0;  // Lower address
    Currency currency1;  // Higher address
}

// Uniswap V4 requires currency0 < currency1
function _sortCurrencies(Currency A, Currency B) returns (CurrencyPair)
```

## Hook Integration

### With YieldMaximizerHook
```solidity
PoolKey memory key = PoolKey({
    currency0: config.currency0,
    currency1: config.currency1,
    fee: config.fee,
    tickSpacing: config.tickSpacing,
    hooks: hook  // YieldMaximizerHook integrated from creation
});
```

**Pools are created with YieldMaximizerHook integrated from the start**. This enables automatic yield maximization from the moment liquidity is provided.

## Use Cases Enabled

### Small Volume Testing (USDC/DAI)
- **Low fees** encourage frequent small trades
- **Stable prices** minimize impermanent loss
- **Perfect for** testing basic compounding logic

### Medium Volume Testing (WETH/USDC, WETH/DAI)
- **Standard fees** represent typical DeFi usage
- **Moderate volatility** for realistic scenarios
- **High liquidity** pools in real markets

### High Volatility Testing (WBTC/WETH)
- **Crypto-to-crypto** pair with higher volatility
- **Tests** auto-compounder under price stress
- **Realistic** impermanent loss scenarios

### Governance Token Testing (YIELD/WETH)
- **Higher fees** compensate for token risk
- **Price discovery** for new protocol tokens
- **Advanced** yield farming scenarios


## Troubleshooting

**Error: "POOL_MANAGER not found"**
- Run infrastructure deployment first
- Check that POOL_MANAGER is in .env file
- Source .env file: `source .env`

**Error: "HOOK_ADDRESS not found"**
- Run hook deployment first (script/02_DeployHook.s.sol)
- Check that HOOK_ADDRESS is in .env file
- Ensure hook deployment completed successfully

**Error: "TOKEN_WETH not found"**
- Run token creation first
- Verify TOKEN_* addresses in .env
- Use `./scripts/local/run-local-env.sh` for automatic setup

**Pool initialization fails**
- Check token addresses are valid contracts
- Verify PoolManager is deployed correctly
- Ensure sufficient gas limits

**Price calculation errors**
- Prices are simplified for testing
- In production, use proper price oracles
- Current prices assume: ETH=$2500, BTC=$50k

## Pool Information Storage

**Generated `deployments/pools.env`:**
```bash
# Created Pool Information
TOTAL_POOLS=5

POOL_0_ID=0x1234...
POOL_0_CURRENCY0=0x0165...  # USDC
POOL_0_CURRENCY1=0x5FC8...  # WETH
POOL_0_FEE=3000

POOL_1_ID=0x5678...
# ... etc for all 5 pools
```

## Gas Usage

- **Per pool creation**: ~200,000 gas
- **Total deployment**: ~1,000,000 gas
- **Cost on Anvil**: ~0.001 ETH total
