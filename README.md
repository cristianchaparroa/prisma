# Prisma

---

## 🚨 The Problem

**DeFi users are losing money due to manual compounding inefficiencies:**

- Individual compounding costs $5-50+ in gas fees
- Most users compound monthly instead of optimal daily/weekly
- Complex yield strategies require constant monitoring
- $100B+ DeFi TVL earning suboptimal returns

**Real Impact:** A $10K position loses $400-800 annually due to these inefficiencies.

---

## 💡 Our Solution

**Prisma YieldMaximizer = native auto-compounder for Uniswap V4**

### What it does:
- **Automatically compounds** trading fees back into LP positions
- **Batches multiple users** together to reduce gas costs
- **Set-and-forget** experience - activate once, earn forever
- **Real-time optimization** based on market conditions

### Why it works:
- Built directly into Uniswap V4 using hooks architecture
- No external dependencies or complex integrations
- Network effects: more users = better efficiency for everyone

---

## 🎯 What Makes Us Unique

### ✅ **Already Built & Working**
- Complete smart contract implementation
- Live dashboard with real-time blockchain events
- Comprehensive testing with 9 user scenarios
- Multi-token support (USDC, WETH, DAI, WBTC)

### ✅ **Mover Advantage**
- Auto-compounder built for Uniswap V4 hooks
- Captures entire emerging market
- Built for the future of DeFi infrastructure

### ✅ **Clear Value Proposition**
- Users earn more with zero effort
- ROI visible from day one

---

## 📊 Market Opportunity

- **$100B+ DeFi TVL** needs yield optimization
- **40% annual growth** in DeFi market size
- **2M+ liquidity providers** seeking better returns

---

## 🚀 What We've Built

### **Technical Achievement:**
- ✅ Native Uniswap V4 hook implementation
- ✅ Batching system for gas optimization
- ✅ Real-time event monitoring dashboard
- ✅ Multi-pool, multi-token support
- ✅ Complete local testing environment

### **Live Demo Available:**
Our working implementation shows actual fee collection, compounding, and gas optimization in real-time.

---

## Local environment

**Environment Details:**
- **Anvil RPC**: `http://localhost:8545`
- **Chain ID**: `31337`
- **Mainnet Fork**: Uses real mainnet contracts and whale funding
- **Test Accounts**: 9 funded accounts for diverse trading scenarios

---

## 🚀 **Quick Start**

### **Prerequisites**

1. **Foundry installed** (https://getfoundry.sh)
2. **Mainnet RPC URL** from:
   - Alchemy: https://alchemy.com
   - Infura: https://infura.io  
   - Public: https://ethereum.publicnode.com
   

### Get the code
```bash
git clone git@github.com:cristianchaparroa/prisma.git
cd prisma
```


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

### Get the Hook address
Once it is done, get the Hook address from the `.env` file. Open the `web/src/App.tsx` file and set it
in the event listener. 


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

Open the web application 
```
http://localhost:5173/
```

### 2. Execute the simulation

```bash
./scripts/local/execute-simulation.sh
```




