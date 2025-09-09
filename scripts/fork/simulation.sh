#!/bin/bash
# YieldMaximizer Fork Simulation Pipeline
# Uses real mainnet tokens and infrastructure

set -e

echo "🚀 Starting YieldMaximizer Fork Simulation Pipeline..."

# Verify fork environment is running
if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil fork not running. Start with:"
    echo "   ./scripts/fork/run-complete-fork.sh <MAINNET_RPC_URL>"
    exit 1
fi

# Source environment
source .env

# Verify required contracts are deployed
REQUIRED_VARS=("HOOK_ADDRESS" "POOL_MANAGER" "POSITION_MANAGER")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ $var not set. Run complete fork setup first."
        exit 1
    fi
done

echo "✅ Fork environment verified"

# Phase 2: Run User Simulation
echo ""
echo "🎭 Phase 2: Simulating users with real tokens..."
forge script script/simulation/07_SimulateUsers.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

# Phase 3: Generate Trading Activity
echo ""
echo "📈 Phase 3: Generating realistic trading activity..."
forge script script/simulation/08_GenerateTrading.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

echo ""
echo "🎉 FORK SIMULATION COMPLETE!"
echo "Ready for yield monitoring and performance testing"
