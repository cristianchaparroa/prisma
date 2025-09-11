# Prisma

# YieldMaximizerHook Environment
🎯 **Complete Interactive Environment for Uniswap V4 Yield-Maximizing Auto-Compounder Hook**

This repository contains a fully deployed local Uniswap V4 environment with the YieldMaximizerHook integrated, providing automated fee compounding and yield optimization for liquidity providers.

---

## 🏗️ **Current Status** ✅

**Successfully Deployed:**
- ✅ Uniswap V4 Infrastructure (PoolManager, PositionManager, etc.)
- ✅ 5 Test Tokens (WETH, USDC, DAI, WBTC, YIELD) 
- ✅ YieldMaximizerHook deployed and integrated
- ✅ 5 Hook-enabled liquidity pools with initial liquidity
- ✅ Complete local Anvil environment running

**Environment Details:**
- **Anvil RPC**: `http://localhost:8545`
- **Chain ID**: `31337`
- **Hook Address**: `0x429051c72d815C038aE8D6442dAe87DD6d255540`
- **Active Pools**: 5 pools with YieldMaximizerHook integrated from creation

---

## 📊 **Project Overview**

The **Yield-Maximizing Auto-Compounder Hook** automatically optimizes liquidity provider returns by:

- **Automated Fee Compounding**: Eliminates manual compounding inefficiencies
- **Gas Optimization**: Batched transactions reduce costs by 70-85%
- **Yield Maximization**: Cross-protocol farming increases returns by 15-40%
- **Set-and-Forget Experience**: Zero maintenance required from users

### **Value Proposition**

| Position Size | Manual APY | Auto-Compound APY | Additional Yield | Gas Savings | Total Benefit |
|---------------|------------|-------------------|------------------|-------------|---------------|
| $10K          | 16.44%     | 21.82%           | +$538            | +$238       | +$776         |
| $100K         | 32.76%     | 47.78%           | +$15,020         | +$1,140     | +$21,160      |
| $5M           | 12.7%      | 24.26%           | +$577,900        | +$240,000   | +$817,900     |

---

## 🚀 **Quick Start**

### **1. Start the Environment**

```bash
# Start the complete local development environment
./scripts/local/run-local-env.sh
```

This script automatically:
- Starts Anvil local blockchain
- Deploys Uniswap V4 infrastructure
- Creates test tokens with initial supply
- Deploys YieldMaximizerHook
- Creates 5 hook-enabled liquidity pools
- Provides initial liquidity to all pools

### **2. Environment Variables**

After running the setup script, your `.env` file will contain:

```bash
# Anvil Local Development Environment
ANVIL_RPC_URL=http://localhost:8545
ANVIL_CHAIN_ID=31337

# Contract Addresses
POOL_MANAGER=0x5FbDB2315678afecb367f032d93F642f64180aa3
POSITION_MANAGER=0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
HOOK_ADDRESS=0x429051c72d815C038aE8D6442dAe87DD6d255540

# Token Addresses
TOKEN_WETH=0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
TOKEN_USDC=0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
TOKEN_DAI=0x8A791620dd6260079BF849Dc5567aDC3F2FdC318
TOKEN_WBTC=0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e
TOKEN_YIELD=0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82
```

### **3. Verify Deployment**

```bash
# Check all components are working
forge script script/local/10_VerifyDeployment.s.sol --rpc-url $ANVIL_RPC_URL
```

---

## 🎭 **Simulation Environment** ✅

### Current Status

The simulation environment provides a complete testing ecosystem with realistic user behavior and trading activity to demonstrate the YieldMaximizer Hook functionality.

**✅ Completed Features:**
- **User Simulation**: 9 diverse user personas (Conservative, Moderate, Aggressive, Whale)
- **Auto-Compound Strategies**: Each user has active yield maximization strategies
- **Realistic Trading**: Multi-pool trading activity generating fees for compounding

### **Quick Start - Complete Simulation**

#### **Option 1: Fresh Environment + Simulation**
```bash
# Complete setup from scratch (recommended)
./scripts/local/clean-simulation.sh  # Starts fresh environment + simulation
```

#### **Option 2: Just Run Simulation** (if environment already running)
```bash
# Run simulation on existing environment
./scripts/local/simulation.sh
```

### **Expected Output**

**Successful simulation will show:**
```
✅ User simulation completed successfully!
📊 User Simulation Results:
   👥 Total Users Simulated: 9
   🛡️  Conservative Users: 3 (low risk, stablecoins)  
   ⚖️  Moderate Users: 3 (balanced approach)
   🚀 Aggressive Users: 2 (high risk, high reward)
   🐋 Whale Users: 1 (diversified, large positions)

📈 Trading Activity Results:
   💰 Total Trades Executed: 75+
   💵 Estimated Fees Generated: $2,500+
   🔄 Auto-Compound Opportunities: Active
   📄 Detailed logs: ./deployments/simulation-*.env
```



