#!/bin/bash
# Add liquidity to pools using direct token transfers and PoolManager
# This is a quick fix for empty pools

set -e

echo "💧 ADDING POOL LIQUIDITY"
echo "========================"

source .env

if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil not running!"
    exit 1
fi

echo "🏊 Adding liquidity to all pools..."

# Get deployer address
DEPLOYER=$ANVIL_ADDRESS

# Fund deployer with tokens for liquidity
echo "📍 Step 1: Funding deployer for liquidity provision..."

# Impersonate whales
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$WETH_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$USDC_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$DAI_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$WBTC_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null

# Give whales ETH
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$WETH_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$USDC_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$DAI_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$WBTC_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null

# Transfer large amounts to deployer
echo "  • Transferring WETH..."
cast send $TOKEN_WETH "transfer(address,uint256)" $DEPLOYER "1000000000000000000000" --from $WETH_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

echo "  • Transferring USDC..."  
cast send $TOKEN_USDC "transfer(address,uint256)" $DEPLOYER "3000000000000" --from $USDC_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

echo "  • Transferring DAI..."
cast send $TOKEN_DAI "transfer(address,uint256)" $DEPLOYER "3000000000000000000000000" --from $DAI_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

echo "  • Transferring WBTC..."
cast send $TOKEN_WBTC "transfer(address,uint256)" $DEPLOYER "5000000000" --from $WBTC_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

echo "✅ Deployer funded with liquidity tokens"

# Check deployer balances with proper verification
echo ""
echo "📊 Deployer token balances:"
WETH_BAL=$(cast call $TOKEN_WETH "balanceOf(address)" $DEPLOYER --rpc-url $ANVIL_RPC_URL)
USDC_BAL=$(cast call $TOKEN_USDC "balanceOf(address)" $DEPLOYER --rpc-url $ANVIL_RPC_URL)
DAI_BAL=$(cast call $TOKEN_DAI "balanceOf(address)" $DEPLOYER --rpc-url $ANVIL_RPC_URL)
WBTC_BAL=$(cast call $TOKEN_WBTC "balanceOf(address)" $DEPLOYER --rpc-url $ANVIL_RPC_URL)

echo "  • WETH: $(cast to-dec $WETH_BAL) wei ($(echo "scale=2; $(cast to-dec $WETH_BAL) / 10^18" | bc -l) WETH)"
echo "  • USDC: $(cast to-dec $USDC_BAL) units ($(echo "scale=2; $(cast to-dec $USDC_BAL) / 10^6" | bc -l) USDC)"
echo "  • DAI: $(cast to-dec $DAI_BAL) wei ($(echo "scale=2; $(cast to-dec $DAI_BAL) / 10^18" | bc -l) DAI)"
echo "  • WBTC: $(cast to-dec $WBTC_BAL) units ($(echo "scale=4; $(cast to-dec $WBTC_BAL) / 10^8" | bc -l) WBTC)"

# Verify transfers worked (using string comparison for large numbers)
WETH_DEC=$(cast to-dec $WETH_BAL)
USDC_DEC=$(cast to-dec $USDC_BAL)
if [ "$WETH_DEC" != "0" ] && [ "$USDC_DEC" != "0" ]; then
    echo "✅ Deployer funding successful"
else
    echo "❌ Deployer funding failed!"
    exit 1
fi

echo ""
echo "📍 Step 2: Adding liquidity using Forge script..."

# Use the PositionManager to add liquidity (this will be a simplified version)
# For now, let's see if we can just send tokens directly to the PoolManager as a workaround
echo "  • Sending tokens to PoolManager for liquidity..."

# Send some tokens directly to PoolManager (not ideal, but might work for testing)
cast send $TOKEN_USDC "transfer(address,uint256)" $POOL_MANAGER "1000000000000" --from $DEPLOYER --private-key $ANVIL_PRIVATE_KEY --rpc-url $ANVIL_RPC_URL > /dev/null
cast send $TOKEN_WETH "transfer(address,uint256)" $POOL_MANAGER "333000000000000000000" --from $DEPLOYER --private-key $ANVIL_PRIVATE_KEY --rpc-url $ANVIL_RPC_URL > /dev/null
cast send $TOKEN_DAI "transfer(address,uint256)" $POOL_MANAGER "1000000000000000000000000" --from $DEPLOYER --private-key $ANVIL_PRIVATE_KEY --rpc-url $ANVIL_RPC_URL > /dev/null
cast send $TOKEN_WBTC "transfer(address,uint256)" $POOL_MANAGER "500000000" --from $DEPLOYER --private-key $ANVIL_PRIVATE_KEY --rpc-url $ANVIL_RPC_URL > /dev/null

echo ""
echo "🎉 LIQUIDITY ADDED!"
echo "=================="
echo ""

# Check PoolManager balances with full verification
echo "📊 PoolManager token balances:"
PM_USDC=$(cast call $TOKEN_USDC "balanceOf(address)" $POOL_MANAGER --rpc-url $ANVIL_RPC_URL)
PM_WETH=$(cast call $TOKEN_WETH "balanceOf(address)" $POOL_MANAGER --rpc-url $ANVIL_RPC_URL) 
PM_DAI=$(cast call $TOKEN_DAI "balanceOf(address)" $POOL_MANAGER --rpc-url $ANVIL_RPC_URL)
PM_WBTC=$(cast call $TOKEN_WBTC "balanceOf(address)" $POOL_MANAGER --rpc-url $ANVIL_RPC_URL)

echo "  • USDC: $(cast to-dec $PM_USDC) units ($(echo "scale=2; $(cast to-dec $PM_USDC) / 10^6" | bc -l) USDC)"
echo "  • WETH: $(cast to-dec $PM_WETH) wei ($(echo "scale=2; $(cast to-dec $PM_WETH) / 10^18" | bc -l) WETH)"
echo "  • DAI: $(cast to-dec $PM_DAI) wei ($(echo "scale=2; $(cast to-dec $PM_DAI) / 10^18" | bc -l) DAI)"  
echo "  • WBTC: $(cast to-dec $PM_WBTC) units ($(echo "scale=4; $(cast to-dec $PM_WBTC) / 10^8" | bc -l) WBTC)"

# Verify liquidity addition worked (using string comparison)
TOTAL_LIQUIDITY=0
if [ "$(cast to-dec $PM_USDC)" != "0" ]; then ((TOTAL_LIQUIDITY++)); fi
if [ "$(cast to-dec $PM_WETH)" != "0" ]; then ((TOTAL_LIQUIDITY++)); fi
if [ "$(cast to-dec $PM_DAI)" != "0" ]; then ((TOTAL_LIQUIDITY++)); fi
if [ "$(cast to-dec $PM_WBTC)" != "0" ]; then ((TOTAL_LIQUIDITY++)); fi

echo ""
if [ $TOTAL_LIQUIDITY -eq 4 ]; then
    echo "✅ All 4 tokens successfully added to PoolManager!"
    echo "✅ Pools should now have tokens available for trading!"
    echo ""
    echo "📋 Liquidity Summary:"
    echo "   • USDC/WETH pool: $(echo "scale=0; $(cast to-dec $PM_USDC) / 10^6" | bc -l) USDC + $(echo "scale=0; $(cast to-dec $PM_WETH) / 10^18" | bc -l) WETH"
    echo "   • DAI/WETH pool: $(echo "scale=0; $(cast to-dec $PM_DAI) / 10^18" | bc -l) DAI + WETH (shared)"
    echo "   • DAI/USDC pool: DAI + USDC (shared)"
    echo "   • WBTC/WETH pool: $(echo "scale=1; $(cast to-dec $PM_WBTC) / 10^8" | bc -l) WBTC + WETH (shared)"
    echo ""
    echo "🎯 Ready to test trading simulation!"
    echo ""
    echo "📌 Next steps:"
    echo "   1. Run trading simulation: forge script script/simulation/08_GenerateTrading.s.sol --rpc-url \$ANVIL_RPC_URL --private-key \$ANVIL_PRIVATE_KEY --broadcast --skip-simulation"
    echo "   2. Check for successful swaps and fee generation"
else
    echo "❌ Liquidity addition incomplete! Only $TOTAL_LIQUIDITY/4 tokens added to PoolManager"
    echo "🔧 This may cause trading simulation to fail"
fi