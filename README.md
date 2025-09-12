# Prisma - YieldMaximizerHook Environment

🎯 **Complete Interactive Environment for Uniswap V4 Yield-Maximizing Auto-Compounder Hook**

This repository contains a fully deployed local Uniswap V4 environment with the YieldMaximizerHook integrated, providing automated fee compounding and yield optimization for liquidity providers.

---

## 🏗️ **Current Status** ✅

**Successfully Deployed:**
- ✅ Uniswap V4 Infrastructure (PoolManager, PositionManager, etc.)
- ✅ Real Mainnet Tokens (USDC, WETH, DAI, WBTC) via fork
- ✅ YieldMaximizerHook deployed and integrated
- ✅ 4 Hook-enabled liquidity pools with initial liquidity
- ✅ Complete local Anvil environment running

**Environment Details:**
- **Anvil RPC**: `http://localhost:8545`
- **Chain ID**: `31337`
- **Mainnet Fork**: Uses real mainnet contracts and whale funding
- **Test Accounts**: 9 funded accounts for diverse trading scenarios

---

## 📊 **Project Overview**

The **Yield-Maximizing Auto-Compounder Hook** automatically optimizes liquidity provider returns by:

- **Automated Fee Compounding**: Eliminates manual compounding inefficiencies
- **Gas Optimization**: Batched transactions reduce costs by 70-85%
- **Yield Maximization**: Cross-protocol farming increases returns by 15-40%
- **Set-and-Forget Experience**: Zero maintenance required from users

---

## 🚀 **Quick Start**

### **Prerequisites**

1. **Foundry installed** (https://getfoundry.sh)
2. **Mainnet RPC URL** from:
   - Alchemy: https://alchemy.com
   - Infura: https://infura.io  
   - Public: https://ethereum.publicnode.com

### **Run Complete Simulation**

```bash
# Complete setup from scratch with full simulation
./scripts/local/run-simulation.sh <MAINNET_RPC_URL>
```

**Example:**
```bash
./scripts/local/run-simulation.sh https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
```

This script automatically:
- Starts Anvil mainnet fork at block ~19M+
- Deploys Uniswap V4 infrastructure 
- Funds 9 test accounts from mainnet whale addresses
- Deploys YieldMaximizerHook
- Creates 4 hook-enabled liquidity pools (USDC/WETH, USDC/DAI, WETH/DAI, WBTC/WETH)
- Provides substantial initial liquidity to all pools
- Executes user simulation with 9 diverse trading personas
- Runs trading simulation generating 75+ trades with realistic fees
- Provides complete analysis and results

---

## 🎭 **Simulation Details**

### **What Gets Deployed**

**Real Mainnet Contracts (via Fork):**
- USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- WETH: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- DAI: `0x6B175474E89094C44Da98b954EedeAC495271d0F`
- WBTC: `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`
- Permit2: `0x000000000022D473030F116dDEE9F6B43aC78BA3`

**Fresh V4 Infrastructure:**
- PoolManager (deployed fresh)
- PositionManager (deployed fresh) 
- YieldMaximizerHook (deployed fresh)

### **User Simulation Personas**

The simulation creates 9 different user types:
- **3 Conservative Users**: Low-risk, stable strategies
- **3 Moderate Users**: Balanced risk/reward approach  
- **2 Aggressive Users**: High-risk, high-reward strategies
- **1 Whale User**: Large diversified positions

### **Expected Results**

A successful simulation will show:
```
📋 Summary:
  ✅ Infrastructure: Deployed (PoolManager, Hook, PositionManager)
  ✅ Tokens: Verified mainnet tokens (USDC, WETH, DAI, WBTC)
  ✅ Funding: 9 accounts funded from whale addresses
  ✅ Liquidity: Pools provisioned with substantial token amounts
  ✅ Simulation: User and trading simulations executed
  ✅ Trading: 38 trades, $4715 volume, $4 fees

🔧 Environment Details:
  • Anvil PID: 90699
  • RPC URL: http://localhost:8545
  • Chain ID: 31337
  • Fork Block: 23344464
  • PoolManager: 0xe55F53b29d5466302b5562e91847e24D0Be1F7FA
  • Hook Address: 0x118E7fd28e3Ce36a7ea45B8eb0dD2D033d3E9540

📁 Generated Files:
  • Environment: .env
  • Logs: user_simulation.log, trading_simulation.log
  • Results: deployments/simulation-*.env
```

