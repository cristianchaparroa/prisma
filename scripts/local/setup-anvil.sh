#!/bin/bash

# Automated Anvil Setup Script
# This script:
# 1. Starts Anvil and captures account info
# 2. Creates .env file with first account
# 3. Sources the .env file
# 4. Deploys infrastructure automatically

set -e  # Exit on any error

# Change to project root directory
cd "$(dirname "$0")/../.."

echo "🚀 Starting Automated Anvil Setup..."
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

# Optional: Auto-deploy infrastructure
read -p "🚀 Deploy Uniswap V4 Infrastructure now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📦 Deploying Uniswap V4 Infrastructure..."
    forge script script/00_DeployV4Infrastructure.s.sol \
        --rpc-url $ANVIL_RPC_URL \
        --private-key $ANVIL_PRIVATE_KEY \
        --broadcast -v
    
    if [ $? -eq 0 ]; then
        echo "✅ Infrastructure deployed successfully!"
    else
        echo "❌ Infrastructure deployment failed!"
    fi
fi

echo ""
echo "📝 To stop Anvil later, run: kill $ANVIL_PID"
echo "📝 To restart this setup, run: ./scripts/local/setup-anvil.sh"
echo ""
echo "🎉 Ready for development!"
