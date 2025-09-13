#!/bin/bash

echo "🧪 Testing Simple Swap - Hook Call Verification"
echo "=============================================="

# Check if infrastructure is running
if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil not running. Start with: ./scripts/local/run-local-env.sh"
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
echo "  PoolManager: $POOL_MANAGER"
echo "  Hook: $HOOK_ADDRESS"
echo "  USDC: $TOKEN_USDC"
echo "  WETH: $TOKEN_WETH"

echo ""
echo "🔄 Executing simple swap via cast (avoids Foundry callback limitations)..."
echo "This will:"
echo "  1. Use cast to interact with PoolManager directly"
echo "  2. Test if hook events are emitted"
echo "  3. Show transaction logs"

echo ""
echo "👀 WATCH THE ANVIL TERMINAL for hook events!"
echo "   Look for: 'DebugSwapEntered' or 'HookSwap' events"
echo ""

# Calculate pool ID for USDC/WETH with hook
POOL_KEY_HASH=$(cast keccak256 $(cast abi-encode "encode(address,address,uint24,int24,address)" $TOKEN_USDC $TOKEN_WETH 3000 60 $HOOK_ADDRESS))

echo "📍 Pool ID: $POOL_KEY_HASH"

# Check if the pool actually exists first
echo "=== CHECKING POOL EXISTENCE ==="
cast call $POOL_MANAGER "extsload(bytes32)" $POOL_KEY_HASH --rpc-url $ANVIL_RPC_URL || echo "Pool not found or empty"

echo ""
echo "=== ATTEMPTING SWAP VIA FOUNDRY SCRIPT (proper V4 unlock pattern) ==="

# Use the proper Foundry script that implements unlock/callback pattern
echo "Running SimpleSwapTest.s.sol script with proper V4 unlock pattern..."
echo "This script implements IUnlockCallback and uses poolManager.unlock()"
echo ""

forge script script/local/simulation/SimpleSwapTest.s.sol \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation \
    -vvv 2>&1 | tee swap_test.log

echo ""
echo "=== SWAP TEST RESULTS ==="
# Check the log for key indicators
if grep -q "HOOK WAS CALLED! HookSwap event found" swap_test.log; then
    echo "✅ SUCCESS: Hook was called and HookSwap event was emitted!"
    echo "   Your YieldMaximizerHook is working correctly!"
elif grep -q "HOOK WAS NOT CALLED" swap_test.log; then
    echo "❌ FAILURE: Hook was not called during the swap"
    echo "   Check the swap execution logs above"
else
    echo "⚠️  UNKNOWN: Check swap_test.log for detailed results"
fi

echo ""
echo "✅ Simple swap test completed!"
echo ""
echo "🔍 Results Analysis:"
echo "  - If you saw '=== HOOK CALLED: _afterSwap ===' in Anvil logs → Hook is working! ✅"
echo "  - If you didn't see that message → Hook routing issue ❌"
echo "  - Check the Anvil terminal window for console.log output"
echo ""
echo "💡 Next steps based on results:"
echo "  ✅ Hook working: Events should appear in EventCollector"
echo "  ❌ Hook not called: Check pool routing or hook permissions"
