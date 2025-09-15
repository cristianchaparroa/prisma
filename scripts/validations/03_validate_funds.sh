#!/bin/bash
set -e

echo "Validating Token Balances..."

source .env

# Accounts to check
declare -a accounts=(
    "DEPLOYER:$ANVIL_ADDRESS"
    "ACCOUNT_1:$ACCOUNT_1_ADDRESS"
    "ACCOUNT_2:$ACCOUNT_2_ADDRESS"
    "ACCOUNT_3:$ACCOUNT_3_ADDRESS"
    "ACCOUNT_4:$ACCOUNT_4_ADDRESS"
    "ACCOUNT_5:$ACCOUNT_5_ADDRESS"
    "ACCOUNT_6:$ACCOUNT_6_ADDRESS"
    "ACCOUNT_7:$ACCOUNT_7_ADDRESS"
    "ACCOUNT_8:$ACCOUNT_8_ADDRESS"
    "ACCOUNT_9:$ACCOUNT_9_ADDRESS"
)

# Tokens to check
declare -a tokens=(
    "USDC:$TOKEN_USDC:6"
    "WETH:$TOKEN_WETH:18"
    "DAI:$TOKEN_DAI:18"
    "WBTC:$TOKEN_WBTC:8"
)

error_count=0
total_checks=0

for account in "${accounts[@]}"; do
    IFS=':' read -r account_name account_addr <<< "$account"

    if [ -z "$account_addr" ]; then
        echo "ERROR: $account_name address not set"
        ((error_count++))
        continue
    fi

    echo ""
    echo "Checking $account_name ($account_addr):"

    for token in "${tokens[@]}"; do
        IFS=':' read -r token_name token_addr decimals <<< "$token"
        ((total_checks++))

        if [ -z "$token_addr" ]; then
            echo "  ERROR: $token_name address not set"
            ((error_count++))
            continue
        fi

        balance=$(cast call "$token_addr" "balanceOf(address)" "$account_addr" --rpc-url "$ANVIL_RPC_URL" 2>/dev/null || echo "0x00")
        balance_dec=$(cast to-dec "$balance" 2>/dev/null || echo "0")

        if [ "$balance_dec" = "0" ]; then
            echo "  ERROR: $token_name balance is 0"
            ((error_count++))
        else
            # Format balance based on decimals
            readable=$(python3 -c "print(f'{$balance_dec / 10**$decimals:.4f}')" 2>/dev/null || echo "$balance_dec")
            echo "  OK: $token_name balance: $readable"
        fi
    done
done

echo ""
echo "===================="
echo "VALIDATION SUMMARY:"
echo "===================="
echo "Total checks: $total_checks"
echo "Errors found: $error_count"

if [ $error_count -eq 0 ]; then
    echo "SUCCESS: All accounts have token balances"
    exit 0
else
    echo "FAILURE: $error_count accounts have zero token balances"
    echo ""
    echo "Run the funding script to fix zero balances:"
    echo "./02_fund-accounts-manual.sh"
    exit 1
fi
