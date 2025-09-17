#!/bin/bash
set -e

echo "Validating Pool Initialization..."

source .env

# Check required env vars
required_vars=("TOKEN_USDC" "TOKEN_WETH" "TOKEN_DAI" "TOKEN_WBTC" "HOOK_ADDRESS" "ANVIL_RPC_URL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Missing environment variable: $var"
        exit 1
    fi
done

# All 4 pool configurations: name:token0:token1:fee:tickSpacing
declare -a pools=(
    "USDC/WETH:$TOKEN_USDC:$TOKEN_WETH:3000:60"
    "DAI/WETH:$TOKEN_DAI:$TOKEN_WETH:3000:60"
    "DAI/USDC:$TOKEN_DAI:$TOKEN_USDC:3000:60"
    "WBTC/WETH:$TOKEN_WBTC:$TOKEN_WETH:3000:60"
)

STATE_VIEW="0x7ffe42c4a5deea5b0fec41c94c136cf115597227"

echo "Checking all 4 pools..."
echo "======================"

for pool in "${pools[@]}"; do
    IFS=':' read -r name token0 token1 fee spacing <<< "$pool"

    # Compute PoolId
    encoded=$(cast abi-encode "encode(address,address,uint24,int24,address)" "$token0" "$token1" "$fee" "$spacing" "$HOOK_ADDRESS")
    poolid=$(cast keccak "$encoded")

    # Check initialization
    result=$(cast call "$STATE_VIEW" "getSlot0(bytes32)" "$poolid" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
    sqrtPrice=$(echo "$result" | cut -c1-66)

    if [ "$sqrtPrice" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        echo "❌ Pool $name (fee: $fee): NOT INITIALIZED"
    else
        echo "✅ Pool $name (fee: $fee): INITIALIZED"
    fi
done

echo ""
echo "Pool validation complete"
echo ""
echo "Summary:"
echo "✅ = Pool initialized and ready"
echo "❌ = Pool not initialized (run pool creation script)"
