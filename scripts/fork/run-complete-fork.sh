#!/bin/bash
# Master Fork Setup - Complete Mainnet Environment in One Command

set -e

echo "🚀 Setting up Complete Mainnet Fork Environment..."

# Validate RPC URL
if [ -z "$1" ]; then
    echo "Usage: ./run-complete-fork.sh <MAINNET_RPC_URL>"
    echo "Example: ./run-complete-fork.sh https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
    echo ""
    echo "Get free RPC from:"
    echo "- Alchemy: https://alchemy.com"
    echo "- Infura: https://infura.io"
    echo "- Public: https://ethereum.publicnode.com"
    exit 1
fi

RPC_URL=$1

# Step 1: Setup Anvil Fork
echo "📍 Step 1: Setting up Anvil fork..."

# Clean any existing environment
echo "🧹 Cleaning existing environment..."
pkill -f anvil 2>/dev/null || true
sleep 3

echo "🚀 Starting fresh Anvil fork..."

# Start anvil with optimized fork settings
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

# Wait for full initialization
echo "⏳ Waiting for Anvil fork to sync..."
sleep 8

# Verify connection and fork block
echo "🔍 Verifying fork connection..."
if ! cast block-number --rpc-url http://localhost:8545 >/dev/null 2>&1; then
    echo "❌ Anvil failed to start properly"
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

LATEST_BLOCK=$(cast block-number --rpc-url http://localhost:8545)
echo "✅ Fork active at block: $LATEST_BLOCK"

# Step 2: Create Static Environment Configuration
echo "📍 Step 2: Creating static environment configuration..."

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
TOKEN_USDC=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
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

# Dynamic Deployment Addresses (Will be set by deployment scripts)
# POOL_MANAGER=
# POSITION_MANAGER=
# HOOK_ADDRESS=

# Process Info
ANVIL_PID=$ANVIL_PID
MAINNET_RPC_URL=$RPC_URL
EOF

echo "✅ Static environment created with verified mainnet addresses"

# Test real mainnet contracts
echo "🧪 Testing real mainnet contracts..."
echo "USDC Symbol: $(cast call 0xA0b86a33E6441E2db4e4d6a70eE22dF8F0d0FaC0 "symbol()" --rpc-url http://localhost:8545)"
echo "WETH Symbol: $(cast call 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 "symbol()" --rpc-url http://localhost:8545)"
echo "DAI Symbol: $(cast call 0x6B175474E89094C44Da98b954EedeAC495271d0F "symbol()" --rpc-url http://localhost:8545)"

# Source the environment for subsequent steps
source .env

# Wait for full fork sync
echo "⏳ Waiting for fork to fully sync..."
sleep 5

# Step 3: Deploy V4 Infrastructure
echo "📍 Step 3: Deploying minimal V4 infrastructure..."
forge script scripts/fork/01_DeployMinimalV4.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    echo "❌ V4 infrastructure deployment failed!"
    exit 1
fi

# Update environment with deployed addresses
if [ -f "deployments/fork-v4.env" ]; then
    echo "" >> .env
    cat deployments/fork-v4.env >> .env
    source deployments/fork-v4.env
fi

# Step 4: Deploy YieldMaximizerHook
echo "📍 Step 4: Deploying YieldMaximizerHook..."
forge script scripts/fork/03_DeployYieldHook.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    echo "❌ YieldMaximizerHook deployment failed!"
    exit 1
fi

# Update environment with hook address
if [ -f "deployments/fork-hook.env" ]; then
    echo "" >> .env
    cat deployments/fork-hook.env >> .env
    source deployments/fork-hook.env
fi

# Step 5: Fund Test Accounts
echo "📍 Step 5: Funding test accounts with real tokens..."
forge script scripts/fork/02_FundAccounts.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    echo "❌ Account funding failed!"
    exit 1
fi

# Step 6: Create Pools
echo "📍 Step 6: Creating pools with real tokens..."
forge script scripts/fork/04_CreateMainnetPools.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation

if [ $? -ne 0 ]; then
    echo "❌ Pool creation failed!"
    exit 1
fi

echo ""
echo "🎉 COMPLETE MAINNET FORK ENVIRONMENT READY!"
echo "============================================="
echo ""
echo "✅ Real Permit2 contract active"
echo "✅ Real USDC, WETH, DAI, WBTC tokens"
echo "✅ YieldMaximizerHook deployed and active"
echo "✅ 4 main trading pools created"
echo "✅ 5 test accounts funded with real tokens"
echo ""
echo "📁 Environment saved to: .env"
echo "🔧 Anvil Process ID: $ANVIL_PID"
echo ""
echo "🎯 Next Steps:"
echo "1. Run simulations: ./scripts/local/simulation.sh"
echo "2. Test trading: ./scripts/local/simple-swap.sh"
echo "3. Monitor yields: Check your hook performance!"
echo ""
echo "💡 Environment Benefits:"
echo "- No Permit2 issues (using real mainnet contract)"
echo "- No settlement problems (real token implementations)"
echo "- Realistic market conditions (mainnet liquidity)"
echo "- Battle-tested infrastructure"
