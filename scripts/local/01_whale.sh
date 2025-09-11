#!/bin/bash
# Check whale balances to verify they can fund accounts

set -e

echo "🐋 WHALE BALANCE VERIFICATION"
echo "============================="

cd /Users/cristian/workspace-uni/prisma
source .env

if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil not running!"
    exit 1
fi

echo "🔍 Checking whale balances on forked mainnet..."
echo ""

# Function to convert balance to readable format
convert_balance() {
    local balance_hex=$1
    local decimals=$2
    local symbol=$3

    if [ "$balance_hex" = "0x" ] || [ "$balance_hex" = "0x0" ]; then
        echo "0 $symbol"
    else
        local balance_dec=$(cast to-dec $balance_hex 2>/dev/null || echo "0")
        if [ $decimals -eq 18 ]; then
            echo "$(echo "scale=4; $balance_dec / 10^18" | bc -l 2>/dev/null || echo "0") $symbol"
        elif [ $decimals -eq 6 ]; then
            echo "$(echo "scale=2; $balance_dec / 10^6" | bc -l 2>/dev/null || echo "0") $symbol"
        elif [ $decimals -eq 8 ]; then
            echo "$(echo "scale=8; $balance_dec / 10^8" | bc -l 2>/dev/null || echo "0") $symbol"
        fi
    fi
}

echo "📍 USDC Whale: $USDC_WHALE"
USDC_WHALE_BAL=$(cast call $TOKEN_USDC "balanceOf(address)" $USDC_WHALE --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "0x0")
echo "  USDC Balance: $(convert_balance $USDC_WHALE_BAL 6 USDC)"

echo ""
echo "📍 WETH Whale: $WETH_WHALE"
WETH_WHALE_BAL=$(cast call $TOKEN_WETH "balanceOf(address)" $WETH_WHALE --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "0x0")
echo "  WETH Balance: $(convert_balance $WETH_WHALE_BAL 18 WETH)"

echo ""
echo "📍 DAI Whale: $DAI_WHALE"
DAI_WHALE_BAL=$(cast call $TOKEN_DAI "balanceOf(address)" $DAI_WHALE --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "0x0")
echo "  DAI Balance: $(convert_balance $DAI_WHALE_BAL 18 DAI)"

echo ""
echo "📍 WBTC Whale: $WBTC_WHALE"
WBTC_WHALE_BAL=$(cast call $TOKEN_WBTC "balanceOf(address)" $WBTC_WHALE --rpc-url $ANVIL_RPC_URL 2>/dev/null || echo "0x0")
echo "  WBTC Balance: $(convert_balance $WBTC_WHALE_BAL 8 WBTC)"

echo ""
echo "📍 Analysis:"
echo ""

# Check if any whale has zero balance
ZERO_COUNT=0
if [ "$USDC_WHALE_BAL" = "0x0" ] || [ "$USDC_WHALE_BAL" = "0x" ]; then
    echo "❌ USDC whale has ZERO balance!"
    ((ZERO_COUNT++))
else
    echo "✅ USDC whale has tokens"
fi

if [ "$WETH_WHALE_BAL" = "0x0" ] || [ "$WETH_WHALE_BAL" = "0x" ]; then
    echo "❌ WETH whale has ZERO balance!"
    ((ZERO_COUNT++))
else
    echo "✅ WETH whale has tokens"
fi

if [ "$DAI_WHALE_BAL" = "0x0" ] || [ "$DAI_WHALE_BAL" = "0x" ]; then
    echo "❌ DAI whale has ZERO balance!"
    ((ZERO_COUNT++))
else
    echo "✅ DAI whale has tokens"
fi

if [ "$WBTC_WHALE_BAL" = "0x0" ] || [ "$WBTC_WHALE_BAL" = "0x" ]; then
    echo "❌ WBTC whale has ZERO balance!"
    ((ZERO_COUNT++))
else
    echo "✅ WBTC whale has tokens"
fi

echo ""
if [ $ZERO_COUNT -gt 0 ]; then
    echo "🚨 ISSUE FOUND: $ZERO_COUNT whale(s) have zero balances!"
    echo ""
    echo "💡 SOLUTION: Use different whale addresses with actual token holdings"
    echo "   You can find current large holders on Etherscan for each token"
    echo ""
    echo "📝 To fix:"
    echo "1. Go to Etherscan for each token"
    echo "2. Check the 'Holders' tab"
    echo "3. Find addresses with large balances"
    echo "4. Update whale addresses in run-complete-fork.sh"
else
    echo "✅ All whales have token balances!"
    echo "   The funding issue must be somewhere else."
    echo ""
    echo "📝 Check:"
    echo "1. Are the token contract addresses correct?"
    echo "2. Is the funding script transfer logic working?"
    echo "3. Are there any revert conditions in the funding?"
fi

echo ""
echo "🔍 Current token contract addresses:"
echo "  USDC: $TOKEN_USDC"
echo "  DAI:  $TOKEN_DAI"
echo "  WETH: $TOKEN_WETH"
echo "  WBTC: $TOKEN_WBTC"
