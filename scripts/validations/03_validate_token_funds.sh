#!/bin/bash
set -e

echo "Validating Token Funding..."

source .env

# Check if deployer has sufficient tokens for liquidity provision
echo "Checking DEPLOYER funding ($ANVIL_ADDRESS):"

# Required minimum balances for liquidity provision
REQUIRED_USDC="50000000000"      # 50,000 USDC (6 decimals)
REQUIRED_WETH="20000000000000000000"   # 20 WETH (18 decimals)
REQUIRED_DAI="50000000000000000000000"  # 50,000 DAI (18 decimals)
REQUIRED_WBTC="100000000"        # 1 WBTC (8 decimals)

error_count=0

# Check USDC
echo "USDC Balance:"
usdc_balance=$(cast call $TOKEN_USDC "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL)
usdc_dec=$(cast to-dec "$usdc_balance")
usdc_readable=$(python3 -c "print(f'{$usdc_dec / 10**6:.2f}')" 2>/dev/null)
echo "  Current: $usdc_readable USDC ($usdc_dec units)"
echo "  Required: 50,000 USDC ($REQUIRED_USDC units)"

# Use bc for large number comparison
is_insufficient=$(echo "$usdc_dec < $REQUIRED_USDC" | bc 2>/dev/null || echo "1")
if [ "$is_insufficient" = "1" ]; then
    echo "  ERROR: Insufficient USDC funding"
    ((error_count++))
else
    echo "  OK: USDC adequately funded"
fi

# Check WETH
echo ""
echo "WETH Balance:"
weth_balance=$(cast call $TOKEN_WETH "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL)
weth_dec=$(cast to-dec "$weth_balance")
weth_readable=$(python3 -c "print(f'{$weth_dec / 10**18:.4f}')" 2>/dev/null)
echo "  Current: $weth_readable WETH ($weth_dec wei)"
echo "  Required: 20 WETH ($REQUIRED_WETH wei)"

# Use bc for large number comparison
is_insufficient=$(echo "$weth_dec < $REQUIRED_WETH" | bc 2>/dev/null || echo "1")
if [ "$is_insufficient" = "1" ]; then
    echo "  ERROR: Insufficient WETH funding"
    ((error_count++))
else
    echo "  OK: WETH adequately funded"
fi

# Check DAI
echo ""
echo "DAI Balance:"
dai_balance=$(cast call $TOKEN_DAI "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL)
dai_dec=$(cast to-dec "$dai_balance")
dai_readable=$(python3 -c "print(f'{$dai_dec / 10**18:.2f}')" 2>/dev/null)
echo "  Current: $dai_readable DAI ($dai_dec wei)"
echo "  Required: 50,000 DAI ($REQUIRED_DAI wei)"

# Use bc for large number comparison
is_insufficient=$(echo "$dai_dec < $REQUIRED_DAI" | bc 2>/dev/null || echo "1")
if [ "$is_insufficient" = "1" ]; then
    echo "  ERROR: Insufficient DAI funding"
    ((error_count++))
else
    echo "  OK: DAI adequately funded"
fi

# Check WBTC
echo ""
echo "WBTC Balance:"
wbtc_balance=$(cast call $TOKEN_WBTC "balanceOf(address)" $ANVIL_ADDRESS --rpc-url $ANVIL_RPC_URL)
wbtc_dec=$(cast to-dec "$wbtc_balance")
wbtc_readable=$(python3 -c "print(f'{$wbtc_dec / 10**8:.4f}')" 2>/dev/null)
echo "  Current: $wbtc_readable WBTC ($wbtc_dec units)"
echo "  Required: 1 WBTC ($REQUIRED_WBTC units)"

# Use bc for large number comparison
is_insufficient=$(echo "$wbtc_dec < $REQUIRED_WBTC" | bc 2>/dev/null || echo "1")
if [ "$is_insufficient" = "1" ]; then
    echo "  ERROR: Insufficient WBTC funding"
    ((error_count++))
else
    echo "  OK: WBTC adequately funded"
fi

echo ""
echo "===================="
echo "FUNDING VALIDATION:"
echo "===================="

if [ $error_count -eq 0 ]; then
    echo "SUCCESS: Deployer has sufficient token funding for liquidity provision"
    echo "Ready to run liquidity scripts!"
    exit 0
else
    echo "FAILURE: Deployer lacks sufficient funding ($error_count tokens underfunded)"
    echo ""
    echo "Run the funding script to fix this:"
    echo "./fund-accounts.sh"
    exit 1
fi
