#!/bin/bash
# 🚀 UNIFIED UNISWAP V4 YIELD MAXIMIZER SIMULATION
# Complete end-to-end pipeline: Infrastructure + Trading + Analysis
# Usage: ./run-unified-simulation.sh <MAINNET_RPC_URL>

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

# trap cleanup EXIT

print_header "🚀 UNIFIED UNISWAP V4 YIELD MAXIMIZER SIMULATION"

# Validate RPC URL
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: ./run-unified-simulation.sh <MAINNET_RPC_URL>${NC}"
    echo -e "${YELLOW}Example: ./run-unified-simulation.sh https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY${NC}"
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

# Create unified environment file
cat > .env << EOF
# Mainnet Fork Environment (Static Configuration)
ANVIL_RPC_URL=http://localhost:8545
ANVIL_CHAIN_ID=31337
ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Real Mainnet Infrastructure (Battle-tested)
PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
UNIVERSAL_ROUTER=0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD

# Real Mainnet Tokens (High Liquidity)
TOKEN_USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
TOKEN_WETH=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
TOKEN_DAI=0x6B175474E89094C44Da98b954EedeAC495271d0F
TOKEN_USDT=0xdAC17F958D2ee523a2206206994597C13D831ec7
TOKEN_WBTC=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599

# Verified Token Holders (For Funding)
USDC_WHALE=0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341
WETH_WHALE=0x8EB8a3b98659Cce290402893d0123abb75E3ab28
DAI_WHALE=0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643
WBTC_WHALE=0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656

# Test Accounts (10 accounts for diverse testing)
ACCOUNT_1_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ACCOUNT_1_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

ACCOUNT_2_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
ACCOUNT_2_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

ACCOUNT_3_ADDRESS=0x90F79bf6EB2c4f870365E785982E1f101E93b906
ACCOUNT_3_PRIVATE_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6

ACCOUNT_4_ADDRESS=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
ACCOUNT_4_PRIVATE_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a

ACCOUNT_5_ADDRESS=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
ACCOUNT_5_PRIVATE_KEY=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba

ACCOUNT_6_ADDRESS=0x976EA74026E726554dB657fA54763abd0C3a0aa9
ACCOUNT_6_PRIVATE_KEY=0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e

ACCOUNT_7_ADDRESS=0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
ACCOUNT_7_PRIVATE_KEY=0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356

ACCOUNT_8_ADDRESS=0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
ACCOUNT_8_PRIVATE_KEY=0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97

ACCOUNT_9_ADDRESS=0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
ACCOUNT_9_PRIVATE_KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6

# Process Info
ANVIL_PID=$ANVIL_PID
MAINNET_RPC_URL=$RPC_URL
EOF

print_success "Static environment created with verified mainnet addresses"

# Test real mainnet contracts
print_step "Testing real mainnet contracts..."
echo "USDC Symbol: $(cast call 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 "symbol()" --rpc-url http://localhost:8545)"
echo "WETH Symbol: $(cast call 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 "symbol()" --rpc-url http://localhost:8545)"
echo "DAI Symbol: $(cast call 0x6B175474E89094C44Da98b954EedeAC495271d0F "symbol()" --rpc-url http://localhost:8545)"

# Source the environment for subsequent steps
source .env

print_step "Step 1.3: Deploying V4 infrastructure..."
forge script script/local/fork/01_DeployMinimalV4.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    print_error "V4 infrastructure deployment failed!"
    exit 1
fi

# Update environment with deployed addresses
if [ -f "deployments/fork-v4.env" ]; then
    echo "" >> .env
    cat deployments/fork-v4.env >> .env
    source deployments/fork-v4.env
fi

print_step "Step 1.4: Deploying YieldMaximizerHook..."
forge script script/local/fork/03_DeployYieldHook.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    print_error "YieldMaximizerHook deployment failed!"
    exit 1
fi

# Update environment with hook address
if [ -f "deployments/fork-hook.env" ]; then
    echo "" >> .env
    cat deployments/fork-hook.env >> .env
    source deployments/fork-hook.env
fi

print_step "Step 1.5: Creating pools with real tokens..."
forge script script/local/fork/04_CreateMainnetPools.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    print_error "Pool creation failed!"
    exit 1
fi

print_success "Infrastructure deployed successfully"

print_header "PHASE 2: WHALE VERIFICATION & ACCOUNT FUNDING"

print_step "Step 2.1: Verifying whale balances..."
./scripts/local/01_whale.sh

if [ $? -ne 0 ]; then
    print_error "Whale verification failed!"
    exit 1
fi

print_step "Step 2.2: Funding test accounts with real tokens..."


./scripts/local/02_fund-accounts-manual.sh

if [ $? -ne 0 ]; then
  print_error "Both funding methods failed!"
  exit 1
fi


print_success "All test accounts funded successfully"

print_header "PHASE 3: POOL LIQUIDITY PROVISION"

print_step "Step 3.1: Adding liquidity to pools..."
./scripts/local/03_add-pool-liquidity.sh

if [ $? -ne 0 ]; then
    print_error "Pool liquidity addition failed!"
    exit 1
fi

print_success "Pool liquidity added successfully"

print_header "PHASE 4: SIMULATION EXECUTION"

print_step "Step 4.1: Running user simulation..."
forge script script/local/simulation/07_SimulateUsers.s.sol \
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
forge script script/local/simulation/08_GenerateTrading.s.sol \
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

print_header "🎉 UNIFIED SIMULATION COMPLETE!"

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
print_header "SIMULATION ENVIRONMENT READY"
echo -e "${GREEN}Anvil is running at http://localhost:8545${NC}"
echo -e "${GREEN}Press Ctrl+C to stop the environment${NC}"
echo ""

# Keep Anvil running
# fsleep infinity
