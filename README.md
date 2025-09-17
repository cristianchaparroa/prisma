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

### **Create the infrastructure**

```bash
# Complete setup from scratch with full simulation
./scripts/local/run-infra.sh <MAINNET_RPC_URL>
```

**Example:**
```bash
./scripts/local/run-infra.sh https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
```

This script automatically:
- Starts Anvil mainnet fork at block ~19M+
- Deploys Uniswap V4 infrastructure 
- Funds 9 test accounts from mainnet whale addresses
- Deploys YieldMaximizerHook
- Creates 4 hook-enabled liquidity pools (USDC/WETH, USDC/DAI, WETH/DAI, WBTC/WETH)
- Provides initial liquidity to all pools
---

## 🎭 **Simulation Details**

- Executes user simulation with 9 diverse trading personas
- Runs trading simulation generating 75+ trades with realistic fees
- Provides complete analysis and results


### 1. Web

Before start the simulation start the web project
```
cd web
bun install
bun dev
```

### 2. Execute the simulation

```bash
./scripts/local/execute-simulation.sh
```

### 3. Web listener
Once The simulation is executed you could start to see the event listener in the browser 
printing information about the simulation.





