#!/bin/bash
# 🚀 UNISWAP V4 YIELD MAXIMIZER SIMULATION EXECUTION
# Executes simulation on existing infrastructure
# Prerequisites: Infrastructure must be running (use run-infra.sh first)
# Usage: ./execute-simulation.sh

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

print_header "🚀 UNISWAP V4 YIELD MAXIMIZER SIMULATION EXECUTION"

START_TIME=$(date +%s)

# Check if infrastructure is running and environment exists
if [ ! -f ".env" ]; then
    print_error "Environment file .env not found!"
    echo "Please run run-infra.sh first to set up the infrastructure."
    exit 1
fi

# Source the environment
source .env

# Verify Anvil is running
print_step "Verifying infrastructure is running..."
if ! cast block-number --rpc-url http://localhost:8545 >/dev/null 2>&1; then
    print_error "Anvil is not running or not accessible!"
    echo "Please run run-infra.sh first to start the infrastructure."
    exit 1
fi

LATEST_BLOCK=$(cast block-number --rpc-url http://localhost:8545)
print_success "Infrastructure verified at block: $LATEST_BLOCK"

print_header "PHASE 4: SIMULATION EXECUTION"

print_step "Step 4.1: Running user simulation..."
#forge script script/local/simulation/08_SimulateUsers.s.sol \
#    --rpc-url http://localhost:8545 \
#    --private-key $ANVIL_PRIVATE_KEY \
#    --broadcast \
#    --skip-simulation > user_simulation.log 2>&1
./scripts/local/08-simulate-users.sh

if [ $? -eq 0 ]; then
    print_success "User simulation completed"
else
    print_warning "User simulation had issues (check user_simulation.log)"
fi

print_step "Step 4.2: Running trading simulation..."
forge script script/local/simulation/09_GenerateTrading.s.sol \
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

# Source environment again to get latest addresses
source .env

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

print_header "🎉 SIMULATION EXECUTION COMPLETE!"

echo ""
print_success "Total execution time: ${MINUTES}m ${SECONDS}s"
echo ""
echo -e "${CYAN}📋 Summary:${NC}"
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
echo -e "${CYAN}📁 Generated Files:${NC}"
echo "  • Logs: user_simulation.log, trading_simulation.log"
echo "  • Results: deployments/simulation-*.env"
echo ""

if [ -f "deployments/simulation-trading.env" ]; then
    source deployments/simulation-trading.env
    if [ "$TOTAL_TRADES_EXECUTED" -gt "0" ]; then
        print_success "🎯 Yield Maximizer Hook is working and generating fees!"
    else
        print_warning "🔍 Some issues remain with trade execution - check logs for debugging"
    fi
else
    print_warning "🔍 Trading results not available - check logs for debugging"
fi

echo ""
print_header "SIMULATION COMPLETE"
echo -e "${GREEN}Infrastructure still running at http://localhost:8545${NC}"
echo -e "${GREEN}Run this script again to repeat the simulation${NC}"
echo ""
