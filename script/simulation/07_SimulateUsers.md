# 🎭 User Simulation Script - 07_SimulateUsers.s.sol

## 📋 Overview

Creates 9 diverse user personas with different risk profiles and auto-compound strategies. Each user activates YieldMaximizer strategies and provides liquidity to their preferred pools based on their risk tolerance.

## 🚀 Quick Usage

```bash
# Prerequisites: Ensure environment is set up
./scripts/local/run-local-env.sh

# Run user simulation
forge script script/simulation/07_SimulateUsers.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v
```

## 👥 User Personas

### **Conservative Users (Accounts 1-3)**
- **Risk Level**: 2/10
- **Gas Threshold**: 20 gwei
- **Strategy**: Safety-first, prefer stablecoins
- **Pools**: USDC/DAI (60%) + WETH/USDC (40%)
- **Behavior**: Low-risk, frequent compounding

### **Moderate Users (Accounts 4-6)** 
- **Risk Level**: 5/10
- **Gas Threshold**: 50 gwei
- **Strategy**: Balanced diversification
- **Pools**: WETH/USDC (40%) + WETH/DAI (35%) + USDC/DAI (25%)
- **Behavior**: Balanced risk-reward approach

### **Aggressive Users (Accounts 7-8)**
- **Risk Level**: 8/10
- **Gas Threshold**: 100 gwei
- **Strategy**: High-risk, high-reward
- **Pools**: WBTC/WETH (40%) + YIELD/WETH (35%) + WETH/USDC (25%)
- **Behavior**: Risk-tolerant, seeks maximum yield

### **Whale User (Account 9)**
- **Risk Level**: 6/10
- **Gas Threshold**: 75 gwei
- **Strategy**: Full ecosystem participation
- **Pools**: All 5 pools (20% each)
- **Behavior**: Large positions, wide tick ranges

## 🔄 What the Script Does

### **1. Strategy Activation**
```solidity
// For each user's PRIMARY pool only (hook limitation):
yieldHook.activateStrategy(primaryPoolId, gasThreshold, riskLevel);
```

**Important**: Due to YieldMaximizer Hook design, each user can only have ONE active strategy globally, not per pool. Users activate strategy on their primary (first) preferred pool.

### **2. Liquidity Provision**
- Calculates appropriate amounts based on user balance and risk profile
- Whale users: Use full allocation ratios
- Regular users: Use conservative 50% of allocation
- Sets different tick ranges (wider for whales, tighter for conservatives)

### **3. Pool Participation**
| User Type | Primary Strategy | WETH/USDC | WETH/DAI | USDC/DAI | WBTC/WETH | YIELD/WETH |
|-----------|------------------|-----------|----------|----------|-----------|------------|
| Conservative | USDC/DAI ⭐ | LP only | ❌ | ⭐ Strategy | ❌ | ❌ |
| Moderate | WETH/USDC ⭐ | ⭐ Strategy | LP only | LP only | ❌ | ❌ |
| Aggressive | WBTC/WETH ⭐ | LP only | ❌ | ❌ | ⭐ Strategy | LP only |
| Whale | WETH/USDC ⭐ | ⭐ Strategy | LP only | LP only | LP only | LP only |

⭐ = Auto-compound strategy active  
LP only = Liquidity provision without auto-compound

## 📊 Expected Results

### **Console Output**
```bash
🎭 Starting User Simulation with Strategy Activation...
Users to simulate: 9

👤 Simulating user: Conservative_User_1
  Risk Profile: conservative
  Risk Level: 2
  Gas Threshold: 20 gwei
  Preferred Pools: 2
  🔄 Activating strategy for pool: USDC/DAI
  🔄 Activating strategy for pool: WETH/USDC
  💧 Adding liquidity to USDC/DAI with 60% allocation
  ✅ User simulation completed

[... 8 more users ...]

🎉 USER SIMULATION COMPLETE!
✅ All users have active auto-compound strategies
✅ Diverse liquidity positions created
✅ Ready for trading activity generation
```

### **Generated Files**
- **Output**: `./deployments/simulation-users.env`
- **Contains**: User addresses, profiles, risk levels, pool participation

## ⚙️ Configuration Details

### **Risk Level Mapping**
- **1-3**: Conservative (stablecoins, low gas)
- **4-6**: Moderate (balanced approach)
- **7-10**: Aggressive (high-risk assets, high gas tolerance)

### **Gas Threshold Strategy**
- **Conservative**: 20 gwei (compounds only during low gas)
- **Moderate**: 50 gwei (reasonable gas tolerance)
- **Aggressive**: 100 gwei (willing to pay premium for yields)
- **Whale**: 75 gwei (high volume justifies moderate gas)

### **Liquidity Allocation Logic**
```solidity
// Regular users: Conservative liquidity provision
amount = (balance * ratio) / 200; // 50% of target ratio

// Whale users: Full allocation
amount = (balance * ratio) / 100; // Full target ratio
```

## 🔗 Dependencies

### **Required Contracts** (Auto-loaded from environment)
- ✅ `POOL_MANAGER`: Uniswap V4 PoolManager
- ✅ `POSITION_MANAGER`: Position management
- ✅ `HOOK_ADDRESS`: YieldMaximizer Hook
- ✅ `TOKEN_*`: All 5 test tokens (WETH, USDC, DAI, WBTC, YIELD)
- ✅ `PERMIT2`: Token approval system

### **Required Accounts** (Auto-loaded from .env)
- ✅ `ACCOUNT_1_ADDRESS` through `ACCOUNT_9_ADDRESS`
- ✅ `ACCOUNT_1_PRIVATE_KEY` through `ACCOUNT_9_PRIVATE_KEY`

## 🎯 Success Criteria

After successful execution:
- ✅ **9 users** with active auto-compound strategies (one per user)
- ✅ **Strategy diversity** across risk profiles and primary pools
- ✅ **Liquidity distribution** across all 5 pools (with and without strategies)
- ✅ **Different behaviors** ready for testing
- ✅ **Baseline established** for yield measurement on primary pools

## 🔧 Troubleshooting

### **Common Issues**

**"Strategy already active"**
```bash
# Reset environment and re-run setup
./scripts/local/clean-local-env.sh
./scripts/local/run-local-env.sh
```

**"Insufficient tokens"**
```bash
# Ensure token distribution completed
forge script script/local/05_DistributeTokens.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast
```

**"Invalid gas threshold"**
```bash
# Check hook contract MAX_GAS_PRICE constant
# Current limit: 100 gwei
```

### **Verification Commands**

```bash
# Check user strategies are active
cast call $HOOK_ADDRESS "userStrategies(address)(bool,uint256,uint256,uint256,uint256,uint8)" $ACCOUNT_1_ADDRESS

# Check pool participation
cast call $HOOK_ADDRESS "poolStrategies(bytes32)(uint256,uint256,uint256,bool)" $POOL_ID

# Verify liquidity positions
cast call $POSITION_MANAGER "balanceOf(address)" $ACCOUNT_1_ADDRESS
```

## 📈 Next Steps

After running this script:

1. **Verify Results**: Check that all users have active strategies
2. **Run Trading Script**: Execute `08_GenerateTrading.s.sol` to create fees
3. **Monitor Activity**: Use monitoring tools to track auto-compounds
4. **Measure Performance**: Compare yield vs manual compounding

## 🔄 Integration

### **Prerequisite Scripts**
```bash
1. 00_DeployV4Infrastructure.s.sol  # ✅ Must run first
2. 01_CreateTokens.s.sol           # ✅ Must run second  
3. 02_DeployHook.s.sol             # ✅ Must run third
4. 03_CreatePools.s.sol            # ✅ Must run fourth
5. 04_ProvideLiquidity.s.sol       # ✅ Must run fifth
6. 05_DistributeTokens.s.sol       # ✅ Must run sixth
7. 07_SimulateUsers.s.sol          # 🎯 This script
```

### **Follow-up Scripts**
```bash
8. 08_GenerateTrading.s.sol        # Creates trading activity
9. Monitor performance              # Track auto-compound execution
```

---

**🎭 Ready to simulate your diverse user ecosystem!**

This script transforms your YieldMaximizer from a single-user test into a realistic multi-user environment with diverse strategies and behaviors.