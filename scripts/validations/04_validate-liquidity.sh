#!/bin/bash
set -e

echo "Validating Pool Liquidity..."

source .env

# Pool configurations: name,token0,token1,fee,tickSpacing
declare -a pools=(
    "USDC/WETH:$TOKEN_USDC:$TOKEN_WETH:3000:60"
    "DAI/WETH:$TOKEN_DAI:$TOKEN_WETH:3000:60"
    "DAI/USDC:$TOKEN_DAI:$TOKEN_USDC:3000:60"
    "WBTC/WETH:$TOKEN_WBTC:$TOKEN_WETH:3000:60"
)

STATE_VIEW="0x7ffe42c4a5deea5b0fec41c94c136cf115597227"

echo "Pool Status Summary:"
echo "==================="

for pool in "${pools[@]}"; do
    IFS=':' read -r name token0 token1 fee spacing <<< "$pool"

    # Compute PoolId
    encoded=$(cast abi-encode "encode(address,address,uint24,int24,address)" "$token0" "$token1" "$fee" "$spacing" "$HOOK_ADDRESS")
    poolid=$(cast keccak "$encoded")

    # Get pool state
    result=$(cast call "$STATE_VIEW" "getSlot0(bytes32)" "$poolid" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
    liquidity=$(cast call "$STATE_VIEW" "getLiquidity(bytes32)" "$poolid" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x00")

    # Parse results
    sqrtPrice=$(echo "$result" | cut -c1-66)
    tick_hex=$(echo "$result" | cut -c67-130)

    # Check initialization and liquidity
    if [ "$sqrtPrice" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        echo "❌ $name: NOT INITIALIZED"
    else
        # Convert tick from hex to decimal
        tick_dec=$(python3 -c "
import sys
hex_val = '$tick_hex'
if hex_val and hex_val != '0000000000000000000000000000000000000000000000000000000000000000':
    # Handle signed 24-bit integer
    val = int(hex_val, 16)
    if val >= 2**23:
        val -= 2**24
    print(val)
else:
    print(0)
" 2>/dev/null || echo "0")

        # Check liquidity - don't divide by 10^18, show raw units
        liquidity_dec=$(cast to-dec "$liquidity" 2>/dev/null || echo "0")

        if [ "$liquidity_dec" = "0" ]; then
            echo "⚠️  $name: INITIALIZED but NO LIQUIDITY (tick: $tick_dec)"
        else
            # Format liquidity with commas for readability
            liquidity_formatted=$(python3 -c "print(f'{$liquidity_dec:,}')" 2>/dev/null || echo "$liquidity_dec")
            echo "✅ $name: INITIALIZED with LIQUIDITY (tick: $tick_dec, liquidity: $liquidity_formatted units)"
        fi
    fi
done

echo ""
echo "PoolManager Token Balances:"
echo "=========================="

# Check PoolManager balances
echo "Checking PoolManager token reserves..."

for token_name in "USDC" "WETH" "DAI" "WBTC"; do
    token_var="TOKEN_$token_name"
    token_addr=${!token_var}

    if [ -n "$token_addr" ]; then
        balance=$(cast call "$token_addr" "balanceOf(address)" "$POOL_MANAGER" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x00")
        balance_dec=$(cast to-dec "$balance" 2>/dev/null || echo "0")

        # Format based on token decimals
        if [ "$token_name" = "USDC" ]; then
            readable=$(python3 -c "print(f'{$balance_dec / 10**6:,.2f}')" 2>/dev/null || echo "$balance_dec")
            echo "$token_name: $readable ($balance_dec units)"
        elif [ "$token_name" = "WBTC" ]; then
            readable=$(python3 -c "print(f'{$balance_dec / 10**8:,.4f}')" 2>/dev/null || echo "$balance_dec")
            echo "$token_name: $readable ($balance_dec units)"
        else
            readable=$(python3 -c "print(f'{$balance_dec / 10**18:,.4f}')" 2>/dev/null || echo "$balance_dec")
            echo "$token_name: $readable ($balance_dec units)"
        fi
    fi
done

echo ""
echo "NFT Position Info:"
echo "=================="

# Check if position manager is set and get position count
if [ -n "$POSITION_MANAGER" ]; then
    # Get total supply of positions
    total_positions=$(cast call "$POSITION_MANAGER" "totalSupply()" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0")
    total_positions_dec=$(cast to-dec "$total_positions" 2>/dev/null || echo "0")

    echo "Total NFT positions minted: $total_positions_dec"

    # Show first few positions if they exist
    if [ "$total_positions_dec" -gt "0" ]; then
        echo "Position owners:"
        for i in $(seq 1 $total_positions_dec); do
            if [ "$i" -le "5" ]; then  # Only show first 5
                owner=$(cast call "$POSITION_MANAGER" "ownerOf(uint256)" "$i" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x0")
                echo "  Position #$i: $owner"
            fi
        done
        if [ "$total_positions_dec" -gt "5" ]; then
            echo "  ... and $((total_positions_dec - 5)) more"
        fi
    fi
else
    echo "POSITION_MANAGER not set in .env"
fi

echo ""
echo "Summary:"
echo "========"
echo "✅ = Pool initialized with liquidity (ready for trading)"
echo "⚠️  = Pool initialized but no liquidity (swaps will fail)"
echo "❌ = Pool not initialized"
echo ""
echo "Note: Liquidity units are internal V4 units, not token amounts"
