#!/bin/bash
# Manual account funding using Anvil impersonation
# This replaces the failing Solidity funding script

set -e

echo "🏦 MANUAL ACCOUNT FUNDING"
echo "========================="

source .env

if ! curl -s http://localhost:8545 > /dev/null; then
    echo "❌ Anvil not running!"
    exit 1
fi

echo "💰 Funding test accounts with real mainnet tokens..."

# Function to impersonate and fund account
fund_account() {
    local account=$1
    local weth_amount=$2
    local usdc_amount=$3
    local dai_amount=$4
    local wbtc_amount=$5
    local account_name=$6

    echo ""
    echo "📍 Funding $account_name: $account"
    
    # Impersonate whale accounts and give them ETH for gas
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$WETH_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$USDC_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$DAI_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$WBTC_WHALE\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    
    # Give whales ETH for gas
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$WETH_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$USDC_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$DAI_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$WBTC_WHALE\",\"0x21E19E0C9BAB2400000\"],\"id\":1}" -H "Content-Type: application/json" http://localhost:8545 > /dev/null

    # Transfer tokens
    echo "  • WETH: $(echo "scale=2; $weth_amount / 10^18" | bc -l)"
    cast send $TOKEN_WETH "transfer(address,uint256)" $account $weth_amount --from $WETH_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

    echo "  • USDC: $(echo "scale=2; $usdc_amount / 10^6" | bc -l)"
    cast send $TOKEN_USDC "transfer(address,uint256)" $account $usdc_amount --from $USDC_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

    echo "  • DAI: $(echo "scale=2; $dai_amount / 10^18" | bc -l)"
    cast send $TOKEN_DAI "transfer(address,uint256)" $account $dai_amount --from $DAI_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null

    echo "  • WBTC: $(echo "scale=4; $wbtc_amount / 10^8" | bc -l)"
    cast send $TOKEN_WBTC "transfer(address,uint256)" $account $wbtc_amount --from $WBTC_WHALE --unlocked --rpc-url $ANVIL_RPC_URL > /dev/null
    
    echo "  ✅ $account_name funded successfully"
}

# Fund small users (accounts 1-6) - Using string literals for large numbers
WETH_SMALL="20000000000000000000"     # 20 WETH
USDC_SMALL="50000000000"              # 50,000 USDC  
DAI_SMALL="50000000000000000000000"   # 50,000 DAI
WBTC_SMALL="100000000"                # 1 WBTC

fund_account $ACCOUNT_1_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_1"
fund_account $ACCOUNT_2_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_2"
fund_account $ACCOUNT_3_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_3"
fund_account $ACCOUNT_4_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_4"
fund_account $ACCOUNT_5_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_5"
fund_account $ACCOUNT_6_ADDRESS $WETH_SMALL $USDC_SMALL $DAI_SMALL $WBTC_SMALL "Account_6"

# Fund medium users (accounts 7-8)
WETH_MEDIUM="100000000000000000000"     # 100 WETH
USDC_MEDIUM="250000000000"              # 250,000 USDC
DAI_MEDIUM="250000000000000000000000"   # 250,000 DAI  
WBTC_MEDIUM="500000000"                 # 5 WBTC

fund_account $ACCOUNT_7_ADDRESS $WETH_MEDIUM $USDC_MEDIUM $DAI_MEDIUM $WBTC_MEDIUM "Account_7"
fund_account $ACCOUNT_8_ADDRESS $WETH_MEDIUM $USDC_MEDIUM $DAI_MEDIUM $WBTC_MEDIUM "Account_8"

# Fund large user (account 9)  
WETH_LARGE="500000000000000000000"      # 500 WETH
USDC_LARGE="1000000000000"              # 1,000,000 USDC
DAI_LARGE="1000000000000000000000000"   # 1,000,000 DAI
WBTC_LARGE="2000000000"                 # 20 WBTC

fund_account $ACCOUNT_9_ADDRESS $WETH_LARGE $USDC_LARGE $DAI_LARGE $WBTC_LARGE "Account_9"

echo ""
echo "🎉 ALL ACCOUNTS FUNDED SUCCESSFULLY!"
echo "====================================="
echo ""
echo "✅ 9 accounts funded with real mainnet tokens"
echo "✅ Ready for trading simulation"

# Save funding results
cat > ./deployments/fork-funding.env << EOF
# Real Token Funding Results
FUNDING_METHOD=manual_impersonation
TOTAL_FUNDED_ACCOUNTS=9
SMALL_USERS=6
MEDIUM_USERS=2
LARGE_USERS=1
FUNDING_TIMESTAMP=$(date +%s)
EOF

echo "📁 Funding results saved to: ./deployments/fork-funding.env"