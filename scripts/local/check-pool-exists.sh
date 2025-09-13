#!/bin/bash
# Pool existence checker using cast
set -e

# Load environment variables
if [ ! -f ".env" ]; then
    echo "❌ .env file not found!"
    exit 1
fi

source .env

echo "=== POOL EXISTENCE CHECK ==="
echo "Checking for USDC/WETH pool..."
echo ""

# Check if required variables exist
if [ -z "$POOL_MANAGER" ] || [ -z "$HOOK_ADDRESS" ] || [ -z "$TOKEN_USDC" ] || [ -z "$TOKEN_WETH" ]; then
    echo "❌ Missing required environment variables!"
    echo "Required: POOL_MANAGER, HOOK_ADDRESS, TOKEN_USDC, TOKEN_WETH"
    exit 1
fi

echo "Using addresses:"
echo "  PoolManager: $POOL_MANAGER" 
echo "  Hook: $HOOK_ADDRESS"
echo "  USDC: $TOKEN_USDC"
echo "  WETH: $TOKEN_WETH"
echo ""

# Check currency order
if [[ "$TOKEN_USDC" < "$TOKEN_WETH" ]]; then
    echo "✅ Currency order correct: USDC < WETH"
    CURRENCY0=$TOKEN_USDC
    CURRENCY1=$TOKEN_WETH
else
    echo "❌ Currency order incorrect: USDC >= WETH"
    CURRENCY0=$TOKEN_WETH  
    CURRENCY1=$TOKEN_USDC
fi

# Calculate expected pool ID using the same parameters as your test
# fee=3000, tickSpacing=60, hooks=HOOK_ADDRESS
echo ""
echo "Calculating Pool ID with parameters:"
echo "  currency0: $CURRENCY0"
echo "  currency1: $CURRENCY1"  
echo "  fee: 3000"
echo "  tickSpacing: 60"
echo "  hooks: $HOOK_ADDRESS"

# Use cast to calculate the pool ID hash
# This calls the toId() function on a PoolKey struct
CALCULATED_POOL_ID=$(cast keccak256 $(cast abi-encode \
    "encode(address,address,uint24,int24,address)" \
    $CURRENCY0 $CURRENCY1 3000 60 $HOOK_ADDRESS))

echo "Calculated Pool ID: $CALCULATED_POOL_ID"
echo ""

# Use StateView contract to check pool existence (PoolManager doesn't have getSlot0)
STATE_VIEW=0x7ffe42c4a5deea5b0fec41c94c136cf115597227
echo "Checking if pool exists using StateView contract..."
echo "StateView address: $STATE_VIEW"
echo ""

POOL_CHECK_RESULT=$(cast call $STATE_VIEW \
    "getSlot0(bytes32)" \
    "$CALCULATED_POOL_ID" \
    --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "FAILED")

if [ "$POOL_CHECK_RESULT" = "FAILED" ]; then
    echo "❌ Pool does NOT exist with calculated ID: $CALCULATED_POOL_ID"
    echo ""
    echo "This is likely why your swap is failing!"
    echo ""
    echo "Possible causes:"
    echo "  1. Hook address mismatch between deployment and test"
    echo "  2. Pool was never initialized with these exact parameters"
    echo "  3. Different fee tier or tick spacing used during pool creation"
    echo ""
    echo "Check your pool creation logs to see what pools were actually created."
else
    echo "✅ Pool EXISTS!"
    echo "Pool slot0 data: $POOL_CHECK_RESULT"
    
    # Try to get liquidity using StateView
    LIQUIDITY=$(cast call $STATE_VIEW \
        "getLiquidity(bytes32)" \
        "$CALCULATED_POOL_ID" \
        --rpc-url $ANVIL_RPC_URL | cast to-dec)
    
    echo "Pool liquidity: $LIQUIDITY"
    
    if [ "$LIQUIDITY" = "0" ]; then
        echo "⚠️  WARNING: Pool has ZERO liquidity!"
        echo "This will cause swaps to fail even if the pool exists."
    else
        echo "✅ Pool has sufficient liquidity for swaps!"
    fi
fi

echo ""
echo "=== DEBUGGING INFO ==="
echo "Compare with your test script's Pool ID to see if they match."
echo "If they don't match, the hook address is different between deployment and test."
echo ""
echo "=== POOL CHECK COMPLETE ==="
