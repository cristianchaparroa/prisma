#!/usr/bin/env bash
# scripts/validations/05_validate-strategies.sh
set -euo pipefail

# Load .env
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

CONTRACT=${HOOK_ADDRESS:?HOOK_ADDRESS not set}
RPC=${ANVIL_RPC_URL:?ANVIL_RPC_URL not set}

# Collect accounts from env
ACCOUNTS=(
  "$ACCOUNT_1_ADDRESS"
  "$ACCOUNT_2_ADDRESS"
  "$ACCOUNT_3_ADDRESS"
  "$ACCOUNT_4_ADDRESS"
  "$ACCOUNT_5_ADDRESS"
  "$ACCOUNT_6_ADDRESS"
  "$ACCOUNT_7_ADDRESS"
  "$ACCOUNT_8_ADDRESS"
  "$ACCOUNT_9_ADDRESS"
)

for acct in "${ACCOUNTS[@]}"; do
  echo "=== Account: $acct ==="

  # Get tuple
  result=$(cast call "$CONTRACT" \
    "userStrategies(address)(bool,uint256,uint256,uint256,uint256,uint8)" \
    "$acct" \
    --rpc-url "$RPC")

  # Split into array
  read -r isActive totalDeposited totalCompounded lastCompoundTime gasThreshold riskLevel <<<"$result"

  # Print formatted
  echo "  Enabled:        $isActive"
  echo "  Deposited:      $totalDeposited"
  echo "  Compounded:     $totalCompounded"
  echo "  Last Compound:  $lastCompoundTime"
  echo "  Gas Threshold:  $gasThreshold"
  echo "  Risk Level:     $riskLevel"

  if [ "$isActive" = "true" ]; then
    echo "  ✅ Strategy enabled!"
  else
    echo "  ❌ Strategy disabled"
  fi

  echo
done
exit 0
