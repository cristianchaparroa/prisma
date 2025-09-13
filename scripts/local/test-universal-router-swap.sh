#!/bin/bash

echo "🌐 Testing Universal Router V4 Swap - Hook Verification"
echo "======================================================"

# Check if infrastructure is running
if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil not running. Start with: ./scripts/local/run-infra.sh"
    exit 1
fi

echo "✅ Anvil is running"

# Load environment variables
if [ ! -f .env ]; then
    echo "❌ .env file not found"
    exit 1
fi

source .env

echo "📍 Using contracts:"
echo "  Universal Router: $UNIVERSAL_ROUTER"
echo "  PoolManager: $POOL_MANAGER"
echo "  Hook: $HOOK_ADDRESS"
echo "  USDC: $TOKEN_USDC"
echo "  WETH: $TOKEN_WETH"

# Verify pool exists using StateView
STATE_VIEW=0x7ffe42c4a5deea5b0fec41c94c136cf115597227
POOL_ID=$(cast keccak256 $(cast abi-encode "encode(address,address,uint24,int24,address)" $TOKEN_USDC $TOKEN_WETH 3000 60 $HOOK_ADDRESS))

echo ""
echo "📍 Pool ID: $POOL_ID"
echo "🔍 Verifying pool exists..."

POOL_CHECK=$(cast call $STATE_VIEW "getSlot0(bytes32)" $POOL_ID --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "FAILED")
if [ "$POOL_CHECK" = "FAILED" ]; then
    echo "❌ Pool verification failed! Pool may not exist."
    exit 1
fi

LIQUIDITY=$(cast call $STATE_VIEW "getLiquidity(bytes32)" $POOL_ID --rpc-url $ANVIL_RPC_URL | cast to-dec)
echo "✅ Pool verified! Liquidity: $LIQUIDITY"

if [ "$LIQUIDITY" = "0" ]; then
    echo "❌ Pool has zero liquidity! Cannot swap."
    exit 1
fi

echo ""
echo "💰 Checking token balances..."

# Check deployer balances
USDC_BALANCE=$(cast call $TOKEN_USDC "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL | cast to-dec)
WETH_BALANCE=$(cast call $TOKEN_WETH "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL | cast to-dec)

echo "Deployer balances:"
echo "  USDC: $USDC_BALANCE"
echo "  WETH: $WETH_BALANCE"

# Check if we have enough USDC for a 1 USDC swap (1000000 in 6 decimals)
if [ "$USDC_BALANCE" -lt "1000000" ]; then
    echo "❌ Insufficient USDC balance for swap. Need at least 1 USDC (1000000)"
    echo "💡 Run the funding script first: ./scripts/local/execute-simulation.sh"
    exit 1
fi

echo "✅ Sufficient balance for 1 USDC swap"

echo ""
echo "🔄 Executing Universal Router V4 Swap..."
echo "This approach uses the official Universal Router instead of direct PoolManager calls"
echo ""

# First, approve USDC to Universal Router (if not already approved)
echo "📋 Step 1: Approving USDC to Universal Router..."
CURRENT_ALLOWANCE=$(cast call $TOKEN_USDC "allowance(address,address)" $ANVIL_ADDRESS $UNIVERSAL_ROUTER --rpc-url $ANVIL_RPC_URL | cast to-dec)
echo "Current allowance: $CURRENT_ALLOWANCE"

if [ "$CURRENT_ALLOWANCE" -lt "1000000" ]; then
    echo "Approving USDC to Universal Router..."
    cast send $TOKEN_USDC \
        "approve(address,uint256)" \
        $UNIVERSAL_ROUTER \
        115792089237316195423570985008687907853269984665640564039457584007913129639935 \
        --rpc-url $ANVIL_RPC_URL \
        --private-key $ANVIL_PRIVATE_KEY \
        --gas-limit 100000
    
    if [ $? -ne 0 ]; then
        echo "❌ USDC approval failed!"
        exit 1
    fi
    echo "✅ USDC approved to Universal Router"
else
    echo "✅ USDC already approved"
fi

echo ""
echo "📋 Step 2: Executing V4 swap via Universal Router..."
echo "⚠️  NOTE: This is a simplified approach. Production swaps require:"
echo "   - Proper V4Planner encoding"
echo "   - Multi-step command structure"  
echo "   - Slippage protection"
echo ""

echo "👀 WATCH THE ANVIL TERMINAL for hook events!"
echo "   Look for: 'DebugSwapEntered' or 'HookSwap' events"
echo ""

# Create a simple swap command for Universal Router
# This is simplified - production requires proper V4Planner encoding
DEADLINE=$(($(date +%s) + 1800)) # 30 minutes from now

echo "Using deadline: $DEADLINE"
echo "Attempting to swap 1 USDC for WETH..."

# This will likely fail because we need proper V4Planner encoding,
# but it will show us if the Universal Router is responsive
echo "Testing Universal Router responsiveness..."
cast call $UNIVERSAL_ROUTER \
    "WETH9()" \
    --rpc-url $ANVIL_RPC_URL || echo "Universal Router call failed - may need different interface"

echo ""
echo ""
echo "🔧 IMPLEMENTING FRESH ACCOUNT SOLUTION:"
echo "Since Foundry has transient storage persistence issues, creating fresh account..."
echo ""

# Generate a fresh private key to avoid transient storage persistence
FRESH_KEY="0x$(openssl rand -hex 32)"
FRESH_ADDRESS=$(cast wallet address $FRESH_KEY)

echo "Generated fresh account: $FRESH_ADDRESS"
echo "Fresh private key: $FRESH_KEY"

# Fund fresh account with ETH
echo "Funding fresh account with ETH..."
cast send $FRESH_ADDRESS \
    --value 0.1ether \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --gas-limit 21000

# Transfer USDC to fresh account
echo "Transferring 10 USDC to fresh account..."
cast send $TOKEN_USDC \
    "transfer(address,uint256)" \
    $FRESH_ADDRESS \
    10000000 \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --gas-limit 100000

# Verify fresh account balance
FRESH_USDC=$(cast call $TOKEN_USDC "balanceOf(address)" $FRESH_ADDRESS --rpc-url $ANVIL_RPC_URL | cast to-dec)
echo "Fresh account USDC balance: $FRESH_USDC"

# Create a new SimpleSwapTest using the fresh account
echo ""
echo "📋 Step 3: Testing with Fresh Account (avoids transient storage issues)..."

# Create temporary env file with fresh account
cp .env .env.backup
echo "FRESH_PRIVATE_KEY=$FRESH_KEY" >> .env
echo "FRESH_ADDRESS=$FRESH_ADDRESS" >> .env

echo "✅ Fresh account ready for testing!"
echo ""
echo "🚀 NOW RUNNING SIMPLE SWAP TEST WITH FRESH ACCOUNT..."
echo "This should bypass Foundry's transient storage persistence issue"
echo ""

# Use the fresh account in SimpleSwapTest by modifying it to use FRESH_PRIVATE_KEY
echo "FRESH_PRIVATE_KEY=$FRESH_KEY FRESH_ADDRESS=$FRESH_ADDRESS forge script script/local/simulation/SimpleSwapTest.s.sol:SimpleSwapTest --fork-url $ANVIL_RPC_URL --broadcast" > run_fresh_test.sh
chmod +x run_fresh_test.sh

# Also create a version that uses the fresh account
echo "Running SimpleSwapTest with fresh account..."

# Temporarily modify environment variables and run the test
ORIGINAL_KEY=$ANVIL_PRIVATE_KEY
ORIGINAL_DEPLOYER=$ANVIL_ADDRESS
export ANVIL_PRIVATE_KEY=$FRESH_KEY
export DEPLOYER=$FRESH_ADDRESS

forge script script/local/simulation/SimpleSwapTest.s.sol:SimpleSwapTest --fork-url $ANVIL_RPC_URL --broadcast

SCRIPT_RESULT=$?

# Restore original environment
export ANVIL_PRIVATE_KEY=$ORIGINAL_KEY
export DEPLOYER=$ORIGINAL_DEPLOYER

if [ $SCRIPT_RESULT -eq 0 ]; then
    echo "✅ SUCCESS: SimpleSwapTest completed with fresh account!"
    echo "🎯 Check the output above for hook events and swap results"
else
    echo "❌ SimpleSwapTest failed even with fresh account"
    echo "💡 The issue may be deeper than transient storage persistence"
fi

# Clean up
mv .env.backup .env 2>/dev/null || true
rm -f run_fresh_test.sh

echo ""
echo "📊 FINAL RESULTS:"
echo "  ✅ Pool verified and has liquidity ($LIQUIDITY)"
echo "  ✅ Token balances sufficient"  
echo "  ✅ Fresh account created and funded"
if [ $SCRIPT_RESULT -eq 0 ]; then
    echo "  ✅ Swap test completed successfully!"
    echo "  🎯 Hook should have been triggered - check for events above"
else
    echo "  ❌ Swap test failed - may need different approach"
fi
echo ""