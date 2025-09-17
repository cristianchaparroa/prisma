#!/bin/bash

source .env
echo "Hook: $HOOK_ADDRESS"
echo "PoolManager: $POOL_MANAGER"
echo "RPC: $ANVIL_RPC_URL"

if [ -n "$HOOK_ADDRESS" ] && [ -n "$POOL_MANAGER" ]; then
    cast code "$HOOK_ADDRESS" --rpc-url "$ANVIL_RPC_URL" > /dev/null && echo "✅ Hook deployed" || echo "❌ Hook not found"
    poolmgr=$(cast call "$HOOK_ADDRESS" "poolManager()" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null)
    [ -n "$poolmgr" ] && echo "✅ Hook functional" || echo "❌ Hook not functional"
else
    echo "❌ Missing environment variables"
fi
