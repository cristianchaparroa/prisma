#!/bin/bash
#
# This script directly executes the Uniswap V4 hook strategy activation
# and token approvals for a set of test accounts on a live blockchain network (e.g., Anvil).
#
# This is a direct execution script, not a simulation.
# It uses 'curl' for all RPC calls, manually encoding transaction data.
#
# USAGE:
# 1. Ensure you have 'curl' and 'jq' installed.
# 2. Set the following environment variables in a .env file:
#    - ANVIL_RPC_URL: The URL of your blockchain node (e.g., http://localhost:8545)
#    - HOOK_ADDRESS: The deployed address of your YieldMaximizerHook contract
#    - UNIVERSAL_ROUTER: The address of the Uniswap Universal Router
#    - TOKEN_USDC, TOKEN_WETH: Addresses of the tokens to be approved
#    - ACCOUNT_1_ADDRESS, etc.
#    - ACCOUNT_1_PRIVATE_KEY, etc. (required for eth_sendTransaction)
#
# Example:
# source .env
# bash simulate-users.sh

# Exit immediately if a command exits with a non-zero status.
set -e

# Load environment variables
source .env

# --- Dependency Checks ---
if ! command -v curl &> /dev/null
then
    echo "❌ Error: 'curl' command not found."
    echo "Please install curl to run this script."
    exit 1
fi

if ! command -v jq &> /dev/null
then
    echo "❌ Error: 'jq' command not found."
    echo "This script requires 'jq' to parse JSON responses. Please install it."
    exit 1
fi

# --- Environment Variable Checks ---
if [[ -z "$ANVIL_RPC_URL" ]]; then
    echo "❌ Error: ANVIL_RPC_URL environment variable is not set."
    echo "Please set it in your .env file or export it in your terminal."
    exit 1
fi

if [[ -z "$HOOK_ADDRESS" ]]; then
    echo "❌ Error: HOOK_ADDRESS environment variable is not set."
    echo "Please set it in your .env file or export it in your terminal."
    exit 1
fi

if [[ -z "$UNIVERSAL_ROUTER" ]]; then
    echo "❌ Error: UNIVERSAL_ROUTER environment variable is not set."
    echo "Please set it in your .env file or export it in your terminal."
    exit 1
fi

if [[ -z "$TOKEN_WETH" || -z "$TOKEN_USDC" ]]; then
    echo "❌ Error: TOKEN_WETH or TOKEN_USDC environment variables are not set."
    echo "Please set them in your .env file or export them in your terminal."
    exit 1
fi


# Function to encode a hex value to a 32-byte (64 character) hex string
function encode_arg() {
  printf "%064x\n" $1
}

# --- Main Script Logic ---
echo "🚀 Starting Uniswap V4 Hook User Execution..."
echo "RPC URL: $ANVIL_RPC_URL"
echo "Hook Address: $HOOK_ADDRESS"
echo "---"

# Loop through accounts 1 to 9
for i in {1..9}; do
    # Get environment variables for the current user
    ACCOUNT_ADDRESS_VAR="ACCOUNT_${i}_ADDRESS"
    PRIVATE_KEY_VAR="ACCOUNT_${i}_PRIVATE_KEY"

    # Check if the environment variables exist
    if [[ -z "${!ACCOUNT_ADDRESS_VAR}" || -z "${!PRIVATE_KEY_VAR}" ]]; then
        echo "❌ ACCOUNT_${i} environment variables not found. Stopping execution."
        break
    fi

    USER_ADDRESS="${!ACCOUNT_ADDRESS_VAR}"
    PRIVATE_KEY="${!PRIVATE_KEY_VAR}"

    # --- Determine User Profile based on the Solidity logic ---
    if (( i >= 1 && i <= 3 )); then
        PROFILE_NAME="Conservative User $i"
        POOL_ID="0x0000000000000000000000000000000000000000000000000000000000000040" # weth_usdc
        RISK_LEVEL=2
        GAS_THRESHOLD_GWEI=20
    elif (( i >= 4 && i <= 6 )); then
        PROFILE_NAME="Moderate User $i"
        POOL_ID="0x0000000000000000000000000000000000000000000000000000000000000040" # weth_usdc
        RISK_LEVEL=5
        GAS_THRESHOLD_GWEI=50
    elif (( i >= 7 && i <= 8 )); then
        PROFILE_NAME="Aggressive User $i"
        POOL_ID="0x0000000000000000000000000000000000000000000000000000000000000043" # wbtc_weth
        RISK_LEVEL=8
        GAS_THRESHOLD_GWEI=100
    else # Whale User 9
        PROFILE_NAME="Whale User 9"
        POOL_ID="0x0000000000000000000000000000000000000000000000000000000000000040" # weth_usdc
        RISK_LEVEL=6
        GAS_THRESHOLD_GWEI=75
    fi

    # Convert gas threshold from Gwei to Wei (as a decimal number)
    GAS_THRESHOLD_WEI=$(echo "($GAS_THRESHOLD_GWEI * 10^9)" | bc)

    echo "Executing for: $PROFILE_NAME"
    echo "  - Address: $USER_ADDRESS"
    echo "  - Risk Level: $RISK_LEVEL"
    echo "  - Gas Threshold: $GAS_THRESHOLD_GWEI gwei"

    # --- Impersonate account for easier transaction sending ---
    # This is an Anvil-specific RPC call
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$USER_ADDRESS\"],\"id\":$i}" -H "Content-Type: application/json" "$ANVIL_RPC_URL" > /dev/null

    # --- Step 1: Approve Universal Router to spend tokens ---
    # Manually encode approve(address,uint256) call data
    # Function selector is keccak256("approve(address,uint256)")[:4] -> 0x095ea7b3
    # Universal Router address is a 32-byte padded hex string
    ENCODED_ROUTER_ADDRESS=$(echo "$UNIVERSAL_ROUTER" | sed 's/0x//')
    ENCODED_ROUTER_ADDRESS_PADDED=$(printf "%064s\n" $ENCODED_ROUTER_ADDRESS | sed 's/ /0/g')
    # Using hardcoded hex value for uint256 max to avoid printf overflow
    ENCODED_MAX_ALLOWANCE="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    # Approve WETH
    CALL_DATA_APPROVE_WETH="0x095ea7b3$ENCODED_ROUTER_ADDRESS_PADDED$ENCODED_MAX_ALLOWANCE"
    JSON_PAYLOAD_APPROVE_WETH="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$USER_ADDRESS\",\"to\":\"$TOKEN_WETH\",\"data\":\"$CALL_DATA_APPROVE_WETH\"}],\"id\":$i}"
    RESPONSE_APPROVE_WETH=$(curl -s -X POST --data "$JSON_PAYLOAD_APPROVE_WETH" -H "Content-Type: application/json" "$ANVIL_RPC_URL")
    if echo "$RESPONSE_APPROVE_WETH" | jq -e '.error' > /dev/null; then
        echo "❌ WETH approval failed. Response: $(echo "$RESPONSE_APPROVE_WETH" | jq '.error')"
    else
        echo "  ✅ Approved WETH for Universal Router. Tx Hash: $(echo "$RESPONSE_APPROVE_WETH" | jq -r '.result')"
    fi

    # Approve USDC
    CALL_DATA_APPROVE_USDC="0x095ea7b3$ENCODED_ROUTER_ADDRESS_PADDED$ENCODED_MAX_ALLOWANCE"
    JSON_PAYLOAD_APPROVE_USDC="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$USER_ADDRESS\",\"to\":\"$TOKEN_USDC\",\"data\":\"$CALL_DATA_APPROVE_USDC\"}],\"id\":$i}"
    RESPONSE_APPROVE_USDC=$(curl -s -X POST --data "$JSON_PAYLOAD_APPROVE_USDC" -H "Content-Type: application/json" "$ANVIL_RPC_URL")
    if echo "$RESPONSE_APPROVE_USDC" | jq -e '.error' > /dev/null; then
        echo "❌ USDC approval failed. Response: $(echo "$RESPONSE_APPROVE_USDC" | jq '.error')"
    else
        echo "  ✅ Approved USDC for Universal Router. Tx Hash: $(echo "$RESPONSE_APPROVE_USDC" | jq -r '.result')"
    fi


    # --- Step 2: Check and Activate/Update Strategy ---
    # Manually encode getUserStrategy(address) call data
    # Function selector is keccak256("getUserStrategy(address)")[:4] -> 0x2e48719f
    # User address is a 32-byte padded hex string
    ENCODED_USER_ADDRESS=$(echo "$USER_ADDRESS" | sed 's/0x//')
    ENCODED_USER_ADDRESS_PADDED=$(printf "%064s\n" $ENCODED_USER_ADDRESS | sed 's/ /0/g')
    CALL_DATA_GET_STRATEGY="0x2e48719f$ENCODED_USER_ADDRESS_PADDED"

    # Construct JSON-RPC payload for eth_call
    JSON_PAYLOAD_GET_STRATEGY="{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$HOOK_ADDRESS\",\"data\":\"$CALL_DATA_GET_STRATEGY\"},\"latest\"],\"id\":$i}"

    # Make the curl request
    RESPONSE_GET_STRATEGY=$(curl -s -X POST --data "$JSON_PAYLOAD_GET_STRATEGY" -H "Content-Type: application/json" "$ANVIL_RPC_URL")

    # Parse the result and check if the strategy is active
    IS_ACTIVE_HEX=$(echo "$RESPONSE_GET_STRATEGY" | jq -r '.result' | sed 's/0x//' | cut -c 1-64)
    IS_ACTIVE_DEC=$(echo "obase=10; ibase=16; $IS_ACTIVE_HEX" | bc)

    if [[ "$IS_ACTIVE_DEC" -eq 0 ]]; then
        echo "  - Strategy not active. Sending activateStrategy transaction..."

        # Manually encode activateStrategy(bytes32,uint256,uint8)
        # Function selector is keccak256("activateStrategy(bytes32,uint256,uint8)")[:4] -> 0x0f29c420
        # Pool ID is 32 bytes, gas threshold is 32 bytes, risk level is 32 bytes
        POOL_ID_PADDED=$(echo "$POOL_ID" | sed 's/0x//')
        GAS_THRESHOLD_PADDED=$(printf "%064x" $GAS_THRESHOLD_WEI)
        RISK_LEVEL_PADDED=$(printf "%064x" $RISK_LEVEL)

        CALL_DATA_ACTIVATE="0x0f29c420$POOL_ID_PADDED$GAS_THRESHOLD_PADDED$RISK_LEVEL_PADDED"

        # Construct JSON-RPC payload for eth_sendTransaction
        JSON_PAYLOAD_ACTIVATE="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$USER_ADDRESS\",\"to\":\"$HOOK_ADDRESS\",\"data\":\"$CALL_DATA_ACTIVATE\"}],\"id\":$i}"

        # Make the curl request
        RESPONSE_ACTIVATE=$(curl -s -X POST --data "$JSON_PAYLOAD_ACTIVATE" -H "Content-Type: application/json" "$ANVIL_RPC_URL")

        if echo "$RESPONSE_ACTIVATE" | jq -e '.error' > /dev/null; then
            echo "❌ Transaction failed. Response: $(echo "$RESPONSE_ACTIVATE" | jq '.error')"
        else
            echo "  ✅ Activation transaction sent. Tx Hash: $(echo "$RESPONSE_ACTIVATE" | jq -r '.result')"
        fi

    else
        echo "  - Strategy already active. Sending updateStrategy transaction..."

        # Manually encode updateStrategy(uint256,uint8)
        # Function selector is keccak256("updateStrategy(uint256,uint8)")[:4] -> 0x794019a8
        # Gas threshold is 32 bytes, risk level is 32 bytes
        GAS_THRESHOLD_PADDED=$(printf "%064x" $GAS_THRESHOLD_WEI)
        RISK_LEVEL_PADDED=$(printf "%064x" $RISK_LEVEL)

        CALL_DATA_UPDATE="0x794019a8$GAS_THRESHOLD_PADDED$RISK_LEVEL_PADDED"

        # Construct JSON-RPC payload for eth_sendTransaction
        JSON_PAYLOAD_UPDATE="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$USER_ADDRESS\",\"to\":\"$HOOK_ADDRESS\",\"data\":\"$CALL_DATA_UPDATE\"}],\"id\":$i}"

        # Make the curl request
        RESPONSE_UPDATE=$(curl -s -X POST --data "$JSON_PAYLOAD_UPDATE" -H "Content-Type: application/json" "$ANVIL_RPC_URL")

        if echo "$RESPONSE_UPDATE" | jq -e '.error' > /dev/null; then
            echo "❌ Transaction failed. Response: $(echo "$RESPONSE_UPDATE" | jq '.error')"
        else
            echo "  ✅ Update transaction sent. Tx Hash: $(echo "$RESPONSE_UPDATE" | jq -r '.result')"
        fi
    fi

    # Stop impersonating the account for cleanup
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_stopImpersonatingAccount\",\"params\":[\"$USER_ADDRESS\"],\"id\":$i}" -H "Content-Type: application/json" "$ANVIL_RPC_URL" > /dev/null

    echo "---"
done

echo "Script finished successfully!"
