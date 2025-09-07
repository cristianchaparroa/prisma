#!/bin/bash

# Automated Local Development Environment Setup
# This script automatically sets up the complete Uniswap V4 + YieldMaximizerHook environment:
# 1. Starts Anvil and captures account info
# 2. Creates .env file with first account
# 3. Sources the .env file
# 4. Deploys infrastructure
# 5. Creates test tokens
# 6. Deploys Yield Maximizer Hook
# 7. Creates hook-enabled liquidity pools
# 8. Provides initial liquidity to hook-enabled pools

set -e  # Exit on any error

# Running in unattended mode by default
UNATTENDED=true
echo "🤖 Running automated pipeline setup..."

# Change to project root directory
cd "$(dirname "$0")/../.."

echo "🚀 Starting Complete Local Development Environment..."
echo "📂 Working directory: $(pwd)"

# Kill any existing anvil processes
pkill -f anvil || true

echo "📡 Starting Anvil node..."
# Start Anvil in background and capture output
anvil --port 8545 --chain-id 31337 --accounts 10 --balance 10000 > anvil_output.log 2>&1 &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 3

# Check if Anvil started successfully
if ! kill -0 $ANVIL_PID 2>/dev/null; then
    echo "❌ Failed to start Anvil"
    cat anvil_output.log
    exit 1
fi

echo "✅ Anvil started successfully (PID: $ANVIL_PID)"

# Extract account information from log
echo "📋 Extracting account information..."

# Parse accounts (lines that start with (number) and contain ETH)
ACCOUNTS=$(grep "^([0-9])" anvil_output.log | grep "ETH)" | awk '{print $2}')

# Parse private keys (lines between "Private Keys" and "Wallet" sections)
PRIVATE_KEYS=$(awk '/Private Keys/,/Wallet/' anvil_output.log | grep "^([0-9])" | awk '{print $2}')

# Convert to arrays
ACCOUNTS_ARRAY=($ACCOUNTS)
PRIVATE_KEYS_ARRAY=($PRIVATE_KEYS)

# Create accounts.json file
echo "💾 Creating accounts.json file..."
cat > accounts.json << EOF
{
  "anvil": {
    "chainId": 31337,
    "rpcUrl": "http://localhost:8545",
    "accounts": [
EOF

# Add each account to JSON
for i in "${!ACCOUNTS_ARRAY[@]}"; do
    if [ $i -eq $((${#ACCOUNTS_ARRAY[@]} - 1)) ]; then
        # Last item, no comma
        echo "      {" >> accounts.json
        echo "        \"index\": $i," >> accounts.json
        echo "        \"address\": \"${ACCOUNTS_ARRAY[$i]}\"," >> accounts.json
        echo "        \"privateKey\": \"${PRIVATE_KEYS_ARRAY[$i]}\"" >> accounts.json
        echo "      }" >> accounts.json
    else
        echo "      {" >> accounts.json
        echo "        \"index\": $i," >> accounts.json
        echo "        \"address\": \"${ACCOUNTS_ARRAY[$i]}\"," >> accounts.json
        echo "        \"privateKey\": \"${PRIVATE_KEYS_ARRAY[$i]}\"" >> accounts.json
        echo "      }," >> accounts.json
    fi
done

cat >> accounts.json << EOF
    ]
  }
}
EOF

echo "✅ accounts.json created with ${#ACCOUNTS_ARRAY[@]} accounts"

# Create .env file with first account
echo "🔧 Creating .env file..."
cat > .env << EOF
# Anvil Local Development Environment
ANVIL_RPC_URL=http://localhost:8545
ANVIL_CHAIN_ID=31337

# Primary account (Account 0)
ANVIL_PRIVATE_KEY=${PRIVATE_KEYS_ARRAY[0]}
ANVIL_ADDRESS=${ACCOUNTS_ARRAY[0]}

# Additional accounts for testing
ACCOUNT_1_ADDRESS=${ACCOUNTS_ARRAY[1]}
ACCOUNT_1_PRIVATE_KEY=${PRIVATE_KEYS_ARRAY[1]}

ACCOUNT_2_ADDRESS=${ACCOUNTS_ARRAY[2]}
ACCOUNT_2_PRIVATE_KEY=${PRIVATE_KEYS_ARRAY[2]}

ACCOUNT_3_ADDRESS=${ACCOUNTS_ARRAY[3]}
ACCOUNT_3_PRIVATE_KEY=${PRIVATE_KEYS_ARRAY[3]}

# Process ID for cleanup
ANVIL_PID=$ANVIL_PID
EOF

echo "✅ .env file created"

# Source the .env file
echo "🔄 Sourcing .env file..."
source .env

# Create deployments directory for forge scripts
mkdir -p deployments

# Verify setup
echo ""
echo "🎯 Setup Complete!"
echo "   RPC URL: $ANVIL_RPC_URL"
echo "   Chain ID: $ANVIL_CHAIN_ID"
echo "   Primary Account: $ANVIL_ADDRESS"
echo "   Anvil PID: $ANVIL_PID"
echo ""

# Step 1: Deploy Infrastructure
echo "🚀 Step 1: Deploying Uniswap V4 Infrastructure..."
forge script script/local/00_DeployV4Infrastructure.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ Infrastructure deployment failed!"
    exit 1
fi

echo "✅ Infrastructure deployed successfully!"

# Extract PoolManager address and add to .env
if [ -f "./deployments/v4-infrastructure.env" ]; then
    echo "" >> .env
    echo "# Infrastructure Addresses" >> .env
    cat ./deployments/v4-infrastructure.env >> .env
    source .env
    echo "✅ Infrastructure addresses added to environment"
fi

# Step 2: Create Tokens
echo "🪙 Step 2: Creating test tokens (WETH, USDC, DAI, WBTC, YIELD)..."
forge script script/local/01_CreateTokens.s.sol:CreateTokens \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ Token creation failed!"
    exit 1
fi

echo "✅ Test tokens created successfully!"
echo "📄 Token addresses saved to: deployments/tokens.env"

# Extract token addresses and add to .env
echo "📝 Adding token addresses to .env file..."
if [ ! -f "./deployments/tokens.env" ]; then
    echo "⚠️  Token addresses file not found"
    exit 1
fi

echo "" >> .env
echo "# Token Addresses" >> .env
cat ./deployments/tokens.env | sed 's/^/TOKEN_/' >> .env
source .env
echo "✅ Token addresses added to environment"

# Step 3: Deploy Hook
echo "🪝 Step 3: Deploying Yield Maximizer Hook..."
forge script script/local/02_DeployHook.s.sol:DeployHook \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ Hook deployment failed!"
    exit 1
fi

echo "✅ Yield Maximizer Hook deployed successfully!"
echo "📄 Hook info saved to: deployments/hook.env"

# Add hook address to .env
if [ -f "./deployments/hook.env" ]; then
    echo "" >> .env
    echo "# Hook Address" >> .env
    grep "HOOK_ADDRESS=" ./deployments/hook.env >> .env
    source .env
    echo "✅ Hook address added to environment"
fi

# Step 4: Create Hook-Enabled Pools
echo "🏊 Step 4: Creating hook-enabled liquidity pools (WETH/USDC, WETH/DAI, WBTC/WETH, USDC/DAI, YIELD/WETH)..."
forge script script/local/03_CreatePools.s.sol:CreatePools \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ Hook-enabled pool creation failed!"
    exit 1
fi

echo "✅ Hook-enabled liquidity pools created successfully!"
echo "📄 Pool info saved to: deployments/pools.env"

# Step 5: Provide Liquidity
echo "💧 Step 5: Providing initial liquidity to hook-enabled pools..."
forge script script/local/04_ProvideLiquidity.s.sol:ProvideLiquidity \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v

if [ $? -ne 0 ]; then
    echo "❌ Liquidity provision failed!"
    exit 1
fi

echo "✅ Initial liquidity provided to hook-enabled pools successfully!"
echo "📄 Liquidity info saved to: deployments/liquidity.env"

echo ""
echo "🎉 DEVELOPMENT ENVIRONMENT READY!"
echo "   - Anvil running with 10 funded accounts"
echo "   - Uniswap V4 PoolManager deployed"
echo "   - 5 test tokens created and distributed"
echo "   - Yield Maximizer Hook deployed and active"
echo "   - 5 hook-enabled liquidity pools with deep liquidity"
echo "   - Ready for yield maximization!"

echo ""
echo "📝 To stop Anvil later, run: kill $ANVIL_PID"
echo "📝 To restart this setup, run: ./scripts/local/run-local-env.sh"
echo ""
echo "🎉 Ready for development!"
