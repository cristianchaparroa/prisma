# 04_ProvideLiquidity_PositionManager.s.sol

## Overview

This script provides initial liquidity to all Uniswap V4 pools using the **PositionManager** approach. It replaces the original callback-based liquidity provision script that had execution limitations in Forge environments.

## Purpose

- **Mint liquidity positions** across 5 different pools
- **Use PositionManager** for proper settlement patterns
- **Handle token approvals** correctly via SimplePermit2
- **Demonstrate realistic V4 liquidity operations**

## Prerequisites

This script requires the following to be deployed and configured:

1. ✅ **Infrastructure**: PoolManager, PositionManager, SimplePermit2
2. ✅ **Tokens**: WETH, USDC, DAI, WBTC, YIELD with sufficient balances
3. ✅ **Pools**: 5 initialized pools with proper tick spacing
4. ✅ **Environment**: `.env` file with all contract addresses

## Usage

### Standalone Execution
```bash
forge script script/local/04_ProvideLiquidity.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v
```

### Via Automated Pipeline
The script is automatically executed as part of the complete environment setup:
```bash
./scripts/local/run-local-env.sh
```

## Pool Configurations

The script provides liquidity to 5 pools with strategic ranges:

| Pool | Fee | Tick Range | Strategy |
|------|-----|------------|----------|
| WETH/USDC | 3000 (0.3%) | ±600 ticks (~6%) | Major pair, moderate range |
| WETH/DAI | 3000 (0.3%) | ±600 ticks (~6%) | Major pair, moderate range |  
| WBTC/WETH | 3000 (0.3%) | ±600 ticks (~6%) | Volatile pair, moderate range |
| USDC/DAI | 500 (0.05%) | ±100 ticks (~1%) | Stablecoin, tight range |
| YIELD/WETH | 10000 (1%) | ±1000 ticks (~10%) | High-fee, wide range |

## Token Amounts

The script uses realistic amounts based on typical liquidity provision:

```solidity
// Example: WETH/USDC pool
uint256 wethAmount = 4 * 10**18;        // 4 WETH
uint256 usdcAmount = 10000 * 10**6;     // 10,000 USDC
// Ratio: ~$2,500 per WETH
```

### Amount Calculation Logic
```solidity
function _calculateTokenAmounts(PoolConfig memory config) 
    internal view returns (uint256 amount0, uint256 amount1) {
    
    if (keccak256(abi.encodePacked(config.name)) == keccak256("WETH/USDC")) {
        // Determine which token is currency0 vs currency1
        amount0 = Currency.unwrap(config.currency0) == address(weth) ? 4 * 10**18 : 10000 * 10**6;
        amount1 = Currency.unwrap(config.currency1) == address(usdc) ? 10000 * 10**6 : 4 * 10**18;
    }
    // ... similar logic for other pools
}
```

## Expected Output

### Successful Execution Logs
```
Providing liquidity to hook-enabled pools using PositionManager...
Loading contracts from environment variables...
PoolManager loaded: 0x5FbDB2315678afecb367f032d93F642f64180aa3
PositionManager loaded: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
YieldMaximizerHook loaded: 0x429051c72d815C038aE8D6442dAe87DD6d255540
All contracts loaded successfully
Providing liquidity to all hook-enabled pools...

Providing liquidity to pool: WETH/USDC
  Tick range: -600 to 600
  Amount0: 4000000000000000000
  Amount1: 10000000000
 Tokens approved for SimplePermit2
 Position minted via PositionManager
Liquidity provided successfully

[... similar output for other 4 pools ...]

=== LIQUIDITY PROVIDED SUCCESSFULLY ===
```

### Transaction Results
- **Gas Used**: ~350k gas per pool (~1.75M total)
- **Positions Created**: 5 NFT positions (one per pool)
- **Liquidity Added**: Significant depth across all price ranges


## Integration Points

### Before This Script
1. **Infrastructure deployment** (`script/local/00_DeployV4Infrastructure.s.sol`)
2. **Token creation** (`script/local/01_CreateTokens.s.sol`)  
3. **Hook deployment** (`script/local/02_DeployHook.s.sol`)
4. **Pool initialization** (`script/local/03_CreatePools.s.sol`)

### After This Script
- Pools have **deep liquidity** ready for trading
- Environment ready for **hook deployment**
- **NFT positions** can be managed/modified
- Ready for **yield optimization strategies**
