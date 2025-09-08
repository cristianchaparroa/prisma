#!/bin/bash

# YieldMaximizer Simulation Pipeline
# Complete user simulation and trading activity generation
# Prerequisites: Environment must be setup with run-local-env.sh
# 
# This script:
# 1. Simulates 9 diverse users with auto-compound strategies
# 2. Generates 75+ realistic trades to create fees
# 3. Sets up monitoring for auto-compound testing
# 4. Provides performance verification

set -e  # Exit on any error

echo "🎭 Starting YieldMaximizer Complete Simulation Pipeline..."
echo "📂 Working directory: $(pwd)"

# Verify prerequisites
if [ ! -f ".env" ]; then
    echo "❌ Environment not setup. Run ./scripts/local/run-local-env.sh first"
    echo "💡 Complete setup command:"
    echo "   ./scripts/local/run-local-env.sh"
    exit 1
fi

# Source environment variables
source .env

# Verify required environment variables
echo "🔍 Verifying environment setup..."
REQUIRED_VARS=("HOOK_ADDRESS" "POOL_MANAGER" "TOKEN_WETH" "TOKEN_USDC" "ACCOUNT_1_ADDRESS")

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Required environment variable $var not set"
        echo "💡 Run ./scripts/local/run-local-env.sh to setup environment"
        exit 1
    fi
done

echo "✅ Environment verification complete"
echo "   Hook Address: $HOOK_ADDRESS"
echo "   Pool Manager: $POOL_MANAGER"
echo "   RPC URL: $ANVIL_RPC_URL"

# Phase 1: User Simulation
echo ""
echo "🎭 Phase 1: Simulating Diverse Users with Auto-Compound Strategies"
echo "════════════════════════════════════════════════════════════════"
echo "📋 What this does:"
echo "   • Creates 9 different user personas (Conservative, Moderate, Aggressive, Whale)"
echo "   • Activates auto-compound strategies with different risk profiles"
echo "   • Provides liquidity to preferred pools based on user type"
echo "   • Sets up realistic gas thresholds and compound parameters"

echo ""
echo "🚀 Executing user simulation..."
forge script script/simulation/07_SimulateUsers.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ User simulation failed!"
    echo "💡 Check that tokens are distributed: forge script script/local/05_DistributeTokens.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast"
    exit 1
fi

echo "✅ User simulation completed successfully!"

# Verify user simulation results
if [ -f "./deployments/simulation-users.env" ]; then
    echo "📊 User Simulation Results:"
    TOTAL_USERS=$(grep "TOTAL_SIMULATED_USERS=" ./deployments/simulation-users.env | cut -d'=' -f2)
    CONSERVATIVE=$(grep "CONSERVATIVE_USERS=" ./deployments/simulation-users.env | cut -d'=' -f2)
    MODERATE=$(grep "MODERATE_USERS=" ./deployments/simulation-users.env | cut -d'=' -f2)
    AGGRESSIVE=$(grep "AGGRESSIVE_USERS=" ./deployments/simulation-users.env | cut -d'=' -f2)
    WHALE=$(grep "WHALE_USERS=" ./deployments/simulation-users.env | cut -d'=' -f2)
    
    echo "   👥 Total Users Simulated: $TOTAL_USERS"
    echo "   🛡️  Conservative Users: $CONSERVATIVE (low risk, stablecoins)"
    echo "   ⚖️  Moderate Users: $MODERATE (balanced approach)"
    echo "   🚀 Aggressive Users: $AGGRESSIVE (high risk, high reward)"
    echo "   🐋 Whale Users: $WHALE (diversified, large positions)"
    echo "   📄 Details saved to: ./deployments/simulation-users.env"
else
    echo "⚠️  User simulation results file not found"
fi

# Small delay between phases
echo ""
echo "⏱️  Waiting 3 seconds before starting trading generation..."
sleep 3

# Phase 2: Trading Activity Generation
echo ""
echo "📈 Phase 2: Generating Realistic Trading Activity"
echo "════════════════════════════════════════════════"
echo "📋 What this does:"
echo "   • Executes 75+ trades across all 5 pools"
echo "   • Uses weighted distribution (35% WETH/USDC, 25% WETH/DAI, etc.)"
echo "   • Varies trade sizes from $50 (retail) to $25K (whale)"
echo "   • Generates $2K-5K in trading fees for auto-compounding"
echo "   • Creates realistic market activity patterns"

echo ""
echo "Executing trading activity generation..."
forge script script/simulation/08_GenerateTrading.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --force \
    --skip-simulation \
    -v

if [ $? -ne 0 ]; then
    echo "❌ Trading generation failed!"
    echo "💡 Common issues:"
    echo "   - Users need active strategies (run 07_SimulateUsers.s.sol first)"
    echo "   - Insufficient token balances (run 05_DistributeTokens.s.sol)"
    echo "   - Pools need existing liquidity (run 04_ProvideLiquidity.s.sol)"
    exit 1
fi

echo "✅ Trading activity generation completed successfully!"

# Verify trading generation results
if [ -f "./deployments/simulation-trading.env" ]; then
    echo "📊 Trading Activity Results:"
    TOTAL_TRADES=$(grep "TOTAL_TRADES_EXECUTED=" ./deployments/simulation-trading.env | cut -d'=' -f2)
    TOTAL_FEES=$(grep "TOTAL_FEES_GENERATED=" ./deployments/simulation-trading.env | cut -d'=' -f2)
    UNIQUE_TRADERS=$(grep "UNIQUE_TRADERS=" ./deployments/simulation-trading.env | cut -d'=' -f2)
    ACTIVE_POOLS=$(grep "POOLS_WITH_ACTIVITY=" ./deployments/simulation-trading.env | cut -d'=' -f2)
    
    echo "   🔄 Total Trades Executed: $TOTAL_TRADES"
    echo "   💰 Total Fees Generated: $TOTAL_FEES wei"
    echo "   👥 Unique Traders: $UNIQUE_TRADERS"
    echo "   🏊 Pools with Activity: $ACTIVE_POOLS"
    echo "   📄 Details saved to: ./deployments/simulation-trading.env"
    
    # Show pool breakdown
    echo ""
    echo "📊 Pool Activity Breakdown:"
    for i in {0..4}; do
        POOL_NAME=$(grep "POOL_${i}_NAME=" ./deployments/simulation-trading.env | cut -d'=' -f2)
        POOL_TRADES=$(grep "POOL_${i}_TRADES=" ./deployments/simulation-trading.env | cut -d'=' -f2)
        if [ ! -z "$POOL_NAME" ] && [ ! -z "$POOL_TRADES" ]; then
            echo "   🏊 $POOL_NAME: $POOL_TRADES trades"
        fi
    done
else
    echo "⚠️  Trading simulation results file not found"
fi

# Phase 3: Environment Summary
echo ""
echo "🌍 Phase 3: Simulation Environment Summary"
echo "════════════════════════════════════════"

echo "📋 Current State:"
echo "   ✅ Anvil blockchain running on port 8545"
echo "   ✅ YieldMaximizer Hook deployed and active"
echo "   ✅ 5 liquidity pools with hook integration"
echo "   ✅ 9 users with active auto-compound strategies"
echo "   ✅ Realistic trading activity and fee generation"
echo "   ✅ Ready for auto-compound monitoring and testing"

echo ""
echo "🎯 What You Can Do Next:"
echo ""
echo "1. 📊 Monitor Auto-Compound Executions:"
echo "   • Watch for automatic compound triggers"
echo "   • Measure gas savings vs manual compounding"
echo "   • Track yield improvements per user type"
echo ""
echo "2. 🔍 Start Real-time Monitoring:"
echo "   • Set up monitoring dashboard:"
echo "     cd monitoring && npm install"
echo "     ./scripts/monitoring/monitor-viem.sh"
echo "   • Access dashboard: http://localhost:8080"
echo "   • WebSocket feed: ws://localhost:8081"
echo ""
echo "3. 🧪 Run Additional Tests:"
echo "   • Generate more trading: re-run 08_GenerateTrading.s.sol"
echo "   • Test different strategies: modify user risk profiles"
echo "   • Stress testing: increase trade volume and frequency"
echo ""
echo "4. 📈 Measure Performance:"
echo "   • Gas optimization: Individual vs batch compounds"
echo "   • Yield improvement: Auto vs manual compounding"
echo "   • User adoption: Strategy activation rates"

# Quick verification commands
echo ""
echo "🔧 Quick Verification Commands:"
echo ""
echo "# Check user strategy status:"
echo "cast call $HOOK_ADDRESS \"userStrategies(address)(bool,uint256,uint256,uint256,uint256,uint8)\" $ACCOUNT_1_ADDRESS"
echo ""
echo "# Check pool activity:"
echo "cast call $HOOK_ADDRESS \"poolStrategies(bytes32)(uint256,uint256,uint256,bool)\" \$(cast keccak256 \"POOL_ID\")"
echo ""
echo "# Monitor new swaps:"
echo "cast logs --from-block latest --address $POOL_MANAGER \"Swap(bytes32,address,int128,int128,uint160,uint128,int24)\""
echo ""
echo "# Check fee accumulation:"
echo "cast logs --from-block 1 --address $HOOK_ADDRESS \"FeesCollected(address,bytes32,uint256)\""

# Environment information
echo ""
echo "📝 Environment Information:"
echo "   🌐 RPC URL: $ANVIL_RPC_URL"
echo "   🔗 Chain ID: $ANVIL_CHAIN_ID"
echo "   🪝 Hook: $HOOK_ADDRESS"
echo "   🏊 Pool Manager: $POOL_MANAGER"
echo "   💼 Primary Account: $ANVIL_ADDRESS"

# Create summary file
echo ""
echo "💾 Creating simulation summary..."
cat > ./deployments/simulation-summary.env << EOF
# YieldMaximizer Simulation Summary
SIMULATION_COMPLETED=true
SIMULATION_TIMESTAMP=$(date +%s)
SIMULATION_DATE=$(date)

# Environment
RPC_URL=$ANVIL_RPC_URL
CHAIN_ID=$ANVIL_CHAIN_ID
HOOK_ADDRESS=$HOOK_ADDRESS
POOL_MANAGER=$POOL_MANAGER

# Simulation Results
USERS_SIMULATED=true
TRADING_GENERATED=true
READY_FOR_MONITORING=true

# Next Steps
MONITORING_SETUP=false
PERFORMANCE_MEASURED=false
OPTIMIZATION_TESTED=false
EOF

echo "✅ Simulation summary saved to: ./deployments/simulation-summary.env"

echo ""
echo "🎉 YIELDMAXIMIZER SIMULATION PIPELINE COMPLETE!"
echo "════════════════════════════════════════════════"
echo ""
echo "🚀 Your YieldMaximizer Hook is now fully operational with:"
echo "   • 9 diverse users with active auto-compound strategies"
echo "   • 5 pools with realistic trading activity and fee generation"
echo "   • Complete testing environment for performance validation"
echo ""
echo "💡 Ready to demonstrate revolutionary gas savings and yield optimization!"
echo ""
echo "📊 To start monitoring: ./scripts/monitoring/monitor-viem.sh"
echo "🌐 Dashboard will be available at: http://localhost:8080"
echo ""
echo "Happy testing! 🎯"