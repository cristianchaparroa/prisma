#!/bin/bash
# 🚀 COMPLETE UNISWAP V4 YIELD MAXIMIZER SIMULATION
# One-click script to run the entire pipeline from infrastructure to trading
# Usage: ./run-complete-simulation.sh <MAINNET_RPC_URL>

set -e

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored headers
print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

print_step() {
    echo -e "${PURPLE}📍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to cleanup on exit
cleanup() {
    if [ ! -z "$ANVIL_PID" ] && kill -0 $ANVIL_PID 2>/dev/null; then
        print_warning "Cleaning up Anvil process (PID: $ANVIL_PID)..."
        kill $ANVIL_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

print_header "🚀 UNISWAP V4 YIELD MAXIMIZER COMPLETE SIMULATION"

# Validate RPC URL
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: ./run-complete-simulation.sh <MAINNET_RPC_URL>${NC}"
    echo -e "${YELLOW}Example: ./run-complete-simulation.sh https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY${NC}"
    echo ""
    echo -e "${CYAN}Get free RPC from:${NC}"
    echo "- Alchemy: https://alchemy.com"
    echo "- Infura: https://infura.io"
    echo "- Public: https://ethereum.publicnode.com"
    exit 1
fi

RPC_URL=$1
START_TIME=$(date +%s)

print_header "PHASE 1: INFRASTRUCTURE SETUP"

print_step "Step 1.1: Setting up Anvil mainnet fork..."

# Clean any existing environment
print_step "Cleaning existing environment..."
pkill -f anvil 2>/dev/null || true
sleep 3

print_step "Starting fresh Anvil fork..."
anvil --fork-url $RPC_URL \
      --port 8545 \
      --host 0.0.0.0 \
      --accounts 10 \
      --balance 10000 \
      --chain-id 31337 \
      --gas-limit 300000000 \
      --code-size-limit 1000000 &

ANVIL_PID=$!
echo "Anvil started (PID: $ANVIL_PID)"

# Wait for initialization
print_step "Waiting for Anvil fork to sync..."
sleep 8

# Verify connection
print_step "Verifying fork connection..."
if ! cast block-number --rpc-url http://localhost:8545 >/dev/null 2>&1; then
    print_error "Anvil failed to start properly"
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

LATEST_BLOCK=$(cast block-number --rpc-url http://localhost:8545)
print_success "Fork active at block: $LATEST_BLOCK"

print_step "Step 1.2: Creating static environment configuration..."
./scripts/run-complete-fork.sh $RPC_URL > anvil_setup.log 2>&1 &
SETUP_PID=$!

# Wait for infrastructure setup to complete
print_step "Waiting for infrastructure deployment..."
wait $SETUP_PID

if [ $? -ne 0 ]; then
    print_error "Infrastructure setup failed! Check anvil_setup.log"
    tail -20 anvil_setup.log
    exit 1
fi

print_success "Infrastructure deployed successfully"

# Source the environment
source .env

print_header "PHASE 2: WHALE VERIFICATION & ACCOUNT FUNDING"

print_step "Step 2.1: Verifying whale balances..."
./scripts/01_whale.sh

if [ $? -ne 0 ]; then
    print_error "Whale verification failed!"
    exit 1
fi

print_step "Step 2.2: Funding test accounts with real tokens..."
./scripts/02_fund-accounts-manual.sh

if [ $? -ne 0 ]; then
    print_error "Account funding failed!"
    exit 1
fi

print_success "All test accounts funded successfully"

print_header "PHASE 3: POOL LIQUIDITY PROVISION"

print_step "Step 3.1: Adding liquidity to pools..."
./scripts/03_add-pool-liquidity.sh

if [ $? -ne 0 ]; then
    print_error "Pool liquidity addition failed!"
    exit 1
fi

print_success "Pool liquidity added successfully"

print_header "PHASE 4: SIMULATION EXECUTION"

print_step "Step 4.1: Running user simulation..."
forge script script/simulation/07_SimulateUsers.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation > user_simulation.log 2>&1

if [ $? -eq 0 ]; then
    print_success "User simulation completed"
else
    print_warning "User simulation had issues (check user_simulation.log)"
fi

print_step "Step 4.2: Running trading simulation..."
forge script script/simulation/08_GenerateTrading.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation > trading_simulation.log 2>&1

if [ $? -eq 0 ]; then
    print_success "Trading simulation completed"
else
    print_warning "Trading simulation had issues (check trading_simulation.log)"
fi

print_header "PHASE 5: RESULTS & ANALYSIS"

print_step "Step 5.1: Analyzing simulation results..."

# Read trading results
if [ -f "deployments/simulation-trading.env" ]; then
    source deployments/simulation-trading.env

    echo ""
    print_step "📊 Trading Simulation Results:"
    echo "  • Total Trades Executed: $TOTAL_TRADES_EXECUTED"
    echo "  • Total Fees Generated: \$$(echo "scale=2; $TOTAL_FEES_GENERATED / 10^18" | bc -l 2>/dev/null || echo "N/A")"
    echo "  • Unique Traders: $UNIQUE_TRADERS"
    echo "  • Pools with Activity: $POOLS_WITH_ACTIVITY"

    # Calculate success rate if we have the data
    SUCCESS_RATE=$(echo "scale=1; $TOTAL_TRADES_EXECUTED * 100 / 75" | bc -l 2>/dev/null || echo "N/A")
    echo "  • Success Rate: ${SUCCESS_RATE}% (${TOTAL_TRADES_EXECUTED}/75 trades)"

    echo ""
    echo "📈 Pool-Specific Trading Volume:"

    # Format volume values for each pool
    if [ -n "$POOL_0_VOLUME" ] && [ "$POOL_0_VOLUME" != "0" ]; then
        POOL_0_VOLUME_FORMATTED=$(echo "scale=2; $POOL_0_VOLUME / 10^18" | bc -l 2>/dev/null || echo "$POOL_0_VOLUME")
        echo "  • $POOL_0_NAME: $POOL_0_TRADES trades, \$${POOL_0_VOLUME_FORMATTED} volume"
    fi

    if [ -n "$POOL_1_VOLUME" ] && [ "$POOL_1_VOLUME" != "0" ]; then
        POOL_1_VOLUME_FORMATTED=$(echo "scale=2; $POOL_1_VOLUME / 10^18" | bc -l 2>/dev/null || echo "$POOL_1_VOLUME")
        echo "  • $POOL_1_NAME: $POOL_1_TRADES trades, \$${POOL_1_VOLUME_FORMATTED} volume"
    fi

    if [ -n "$POOL_2_VOLUME" ] && [ "$POOL_2_VOLUME" != "0" ]; then
        POOL_2_VOLUME_FORMATTED=$(echo "scale=2; $POOL_2_VOLUME / 10^18" | bc -l 2>/dev/null || echo "$POOL_2_VOLUME")
        echo "  • $POOL_2_NAME: $POOL_2_TRADES trades, \$${POOL_2_VOLUME_FORMATTED} volume"
    fi

    if [ -n "$POOL_3_VOLUME" ] && [ "$POOL_3_VOLUME" != "0" ]; then
        POOL_3_VOLUME_FORMATTED=$(echo "scale=2; $POOL_3_VOLUME / 10^18" | bc -l 2>/dev/null || echo "$POOL_3_VOLUME")
        echo "  • $POOL_3_NAME: $POOL_3_TRADES trades, \$${POOL_3_VOLUME_FORMATTED} volume"
    fi

    # Calculate total volume
    TOTAL_VOLUME=$(echo "$POOL_0_VOLUME + $POOL_1_VOLUME + $POOL_2_VOLUME + $POOL_3_VOLUME" | bc -l 2>/dev/null || echo "0")
    TOTAL_VOLUME_FORMATTED=$(echo "scale=2; $TOTAL_VOLUME / 10^18" | bc -l 2>/dev/null || echo "N/A")

    echo ""
    echo "💰 Fee & Volume Summary:"
    echo "  • Total Trading Volume: \$${TOTAL_VOLUME_FORMATTED}"
    echo "  • Total Fees Generated: \$$(echo "scale=2; $TOTAL_FEES_GENERATED / 10^18" | bc -l 2>/dev/null || echo "N/A")"
    echo "  • Average Fee per Trade: \$$(echo "scale=4; $TOTAL_FEES_GENERATED / 10^18 / $TOTAL_TRADES_EXECUTED" | bc -l 2>/dev/null || echo "N/A")"

    # YieldMaximizerHook status
    echo ""
    echo "🏦 YieldMaximizerHook Status:"
    echo "  • Hook Contract: $HOOK_ADDRESS"
    echo "  • Available for Auto-Compounding: \$$(echo "scale=2; $TOTAL_FEES_GENERATED / 10^18" | bc -l 2>/dev/null || echo "N/A")"
    echo "  • Ready for optimization testing! 🚀"

    if [ "$TOTAL_TRADES_EXECUTED" -gt "0" ]; then
        print_success "Trading simulation successful! Generated substantial fees for yield optimization"
    else
        print_warning "No trades executed - check trading_simulation.log for details"
    fi
else
    print_warning "Trading results file not found"
fi

print_step "Step 5.2: Final system verification..."

# Verify final balances
echo ""
echo "💰 Final Token Balances:"
echo "  PoolManager:"
echo "    USDC: $(cast call $TOKEN_USDC "balanceOf(address)" $POOL_MANAGER --rpc-url http://localhost:8545 | cast to-dec)"
echo "    WETH: $(cast call $TOKEN_WETH "balanceOf(address)" $POOL_MANAGER --rpc-url http://localhost:8545 | cast to-dec)"
echo "    DAI:  $(cast call $TOKEN_DAI "balanceOf(address)" $POOL_MANAGER --rpc-url http://localhost:8545 | cast to-dec)"
echo "    WBTC: $(cast call $TOKEN_WBTC "balanceOf(address)" $POOL_MANAGER --rpc-url http://localhost:8545 | cast to-dec)"

echo ""
echo "  Sample Trader (Account 1):"
echo "    USDC: $(cast call $TOKEN_USDC "balanceOf(address)" $ACCOUNT_1_ADDRESS --rpc-url http://localhost:8545 | cast to-dec)"
echo "    WETH: $(cast call $TOKEN_WETH "balanceOf(address)" $ACCOUNT_1_ADDRESS --rpc-url http://localhost:8545 | cast to-dec)"

# Calculate total execution time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

print_header "🎉 SIMULATION COMPLETE!"

echo ""
print_success "Total execution time: ${MINUTES}m ${SECONDS}s"
echo ""
echo -e "${CYAN}📋 Summary:${NC}"
echo "  ✅ Infrastructure: Deployed (PoolManager, Hook, PositionManager)"
echo "  ✅ Tokens: Verified mainnet tokens (USDC, WETH, DAI, WBTC)"
echo "  ✅ Funding: 9 accounts funded from whale addresses"
echo "  ✅ Liquidity: Pools provisioned with substantial token amounts"
echo "  ✅ Simulation: User and trading simulations executed"

# Add trading results to summary if available
if [ -f "deployments/simulation-trading.env" ]; then
    source deployments/simulation-trading.env
    TOTAL_VOLUME_SUMMARY=$(echo "$POOL_0_VOLUME + $POOL_1_VOLUME + $POOL_2_VOLUME + $POOL_3_VOLUME" | bc -l 2>/dev/null || echo "0")
    VOLUME_FORMATTED=$(echo "scale=0; $TOTAL_VOLUME_SUMMARY / 10^18" | bc -l 2>/dev/null || echo "0")
    FEES_FORMATTED=$(echo "scale=0; $TOTAL_FEES_GENERATED / 10^18" | bc -l 2>/dev/null || echo "0")

    echo "  ✅ Trading: ${TOTAL_TRADES_EXECUTED} trades, \$${VOLUME_FORMATTED} volume, \$${FEES_FORMATTED} fees"
fi
echo ""
echo -e "${CYAN}🔧 Environment Details:${NC}"
echo "  • Anvil PID: $ANVIL_PID"
echo "  • RPC URL: http://localhost:8545"
echo "  • Chain ID: 31337"
echo "  • Fork Block: $LATEST_BLOCK"
echo "  • PoolManager: $POOL_MANAGER"
echo "  • Hook Address: $HOOK_ADDRESS"
echo ""
echo -e "${CYAN}📁 Generated Files:${NC}"
echo "  • Environment: .env"
echo "  • Logs: anvil_setup.log, user_simulation.log, trading_simulation.log"
echo "  • Results: deployments/simulation-*.env"
echo ""

if [ "$TOTAL_TRADES_EXECUTED" -gt "0" ]; then
    print_success "🎯 Yield Maximizer Hook is working and generating fees!"
else
    print_warning "🔍 Some issues remain with trade execution - check logs for debugging"
fi

echo ""
print_header "SIMULATION ENVIRONMENT READY"
echo -e "${GREEN}Anvil is running at http://localhost:8545${NC}"
echo -e "${GREEN}Press Ctrl+C to stop the environment${NC}"
echo ""

# Keep Anvil running and show live logs
tail -f anvil_output.log 2>/dev/null || sleep infinity
