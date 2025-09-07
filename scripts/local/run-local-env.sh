#!/bin/bash

# Automated Local Development Environment Setup
# This script:
# 1. Starts Anvil and captures account info
# 2. Creates .env file with first account
# 3. Sources the .env file
# 4. Deploys infrastructure automatically
# 5. Creates test tokens automatically
# 6. Creates liquidity pools automatically
# 7. Provides initial liquidity automatically

set -e  # Exit on any error

# Check for -y flag for unattended execution
UNATTENDED=false
if [[ "$1" == "-y" || "$1" == "--yes" ]]; then
    UNATTENDED=true
    echo "🤖 Running in unattended mode (auto-accepting all prompts)"
fi

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

# Optional: Auto-deploy infrastructure
if [[ "$UNATTENDED" == "true" ]]; then
    echo "🚀 Auto-deploying Uniswap V4 Infrastructure..."
    REPLY="y"
else
    read -p "🚀 Deploy Uniswap V4 Infrastructure now? (y/n): " -n 1 -r
    echo
fi
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📦 Deploying Uniswap V4 Infrastructure..."
    forge script script/00_DeployV4Infrastructure.s.sol \
        --rpc-url $ANVIL_RPC_URL \
        --private-key $ANVIL_PRIVATE_KEY \
        --broadcast -v

    if [ $? -eq 0 ]; then
        echo "✅ Infrastructure deployed successfully!"

        # Extract PoolManager address and add to .env
        if [ -f "./deployments/v4-infrastructure.env" ]; then
            echo "" >> .env
            echo "# Infrastructure Addresses" >> .env
            cat ./deployments/v4-infrastructure.env >> .env
            source .env
            echo "✅ Infrastructure addresses added to environment"
        fi

        # Optional: Auto-create tokens
        if [[ "$UNATTENDED" == "true" ]]; then
            echo "🪙 Auto-creating test tokens..."
            REPLY="y"
        else
            read -p "🪙 Create test tokens now? (y/n): " -n 1 -r
            echo
        fi
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🪙 Creating test tokens (WETH, USDC, DAI, WBTC, YIELD)..."
            forge script script/01_CreateTokens.s.sol:CreateTokens \
                --rpc-url $ANVIL_RPC_URL \
                --private-key $ANVIL_PRIVATE_KEY \
                --broadcast -v

            if [ $? -eq 0 ]; then
                echo "✅ Test tokens created successfully!"
                echo "📄 Token addresses saved to: deployments/tokens.env"

                # Extract token addresses and add to .env
                echo "📝 Adding token addresses to .env file..."
                if [ -f "./deployments/tokens.env" ]; then
                    echo "" >> .env
                    echo "# Token Addresses" >> .env
                    cat ./deployments/tokens.env | sed 's/^/TOKEN_/' >> .env
                    source .env
                    echo "✅ Token addresses added to environment"

                    # Optional: Auto-create pools
                    if [[ "$UNATTENDED" == "true" ]]; then
                        echo "🏊 Auto-creating liquidity pools..."
                        REPLY="y"
                    else
                        read -p "🏊 Create liquidity pools now? (y/n): " -n 1 -r
                        echo
                    fi
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo "🏊 Creating liquidity pools (WETH/USDC, WETH/DAI, WBTC/WETH, USDC/DAI, YIELD/WETH)..."
                        forge script script/03_CreatePools.s.sol:CreatePools \
                            --rpc-url $ANVIL_RPC_URL \
                            --private-key $ANVIL_PRIVATE_KEY \
                            --broadcast -v

                        if [ $? -eq 0 ]; then
                            echo "✅ Liquidity pools created successfully!"
                            echo "📄 Pool info saved to: deployments/pools.env"

                            # Optional: Auto-provide liquidity
                            if [[ "$UNATTENDED" == "true" ]]; then
                                echo "💧 Auto-providing initial liquidity..."
                                REPLY="y"
                            else
                                read -p "💧 Provide initial liquidity to pools now? (y/n): " -n 1 -r
                                echo
                            fi
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                echo "💧 Providing initial liquidity to all pools..."
                                forge script script/04_ProvideLiquidity.s.sol:ProvideLiquidity \
                                    --rpc-url $ANVIL_RPC_URL \
                                    --private-key $ANVIL_PRIVATE_KEY \
                                    --broadcast -v

                                if [ $? -eq 0 ]; then
                                    echo "✅ Initial liquidity provided successfully!"
                                    echo "📄 Liquidity info saved to: deployments/liquidity.env"
                                    echo ""
                                    echo "🎉 COMPLETE DEVELOPMENT ENVIRONMENT READY!"
                                    echo "   - Anvil running with 10 funded accounts"
                                    echo "   - Uniswap V4 PoolManager deployed"
                                    echo "   - 5 test tokens created and distributed"
                                    echo "   - 5 liquidity pools with deep liquidity"
                                    echo "   - Ready for Yield Maximizer hook deployment"
                                else
                                    echo "❌ Liquidity provision failed!"
                                fi
                            fi
                        else
                            echo "❌ Pool creation failed!"
                        fi
                    fi
                else
                    echo "⚠️  Token addresses file not found"
                fi
            else
                echo "❌ Token creation failed!"
            fi
        fi
    else
        echo "❌ Infrastructure deployment failed!"
    fi
fi

echo ""
echo "📝 To stop Anvil later, run: kill $ANVIL_PID"
echo "📝 To restart this setup, run: ./scripts/local/run-local-env.sh [-y for unattended]"
echo ""
echo "🎉 Ready for development!"
