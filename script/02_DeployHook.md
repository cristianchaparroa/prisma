# Deploy Yield Maximizer Hook Script

## Overview
The `02_DeployHook.s.sol` script deploys the YieldMaximizerHook contract to the local Anvil environment with proper Uniswap V4 hook permissions and address requirements.

## Purpose
This script is part of the local development pipeline and handles the deployment of the custom Uniswap V4 hook that enables automated yield maximization through fee compounding.

## Prerequisites
- Anvil running locally (`anvil --fork-url $MAINNET_RPC_URL`)
- PoolManager already deployed (via `00_DeployV4Infrastructure.s.sol`)
- Test tokens created (via `01_CreateTokens.s.sol`)
- Environment variables set in `.env` file

## Required Environment Variables
```bash
ANVIL_PRIVATE_KEY=0x...
POOL_MANAGER=0x...  # From infrastructure deployment
TOKEN_WETH=0x...    # From token creation
TOKEN_USDC=0x...    # From token creation
# ... other token addresses
```

## Usage

### Basic Deployment
```bash
forge script script/02_DeployHook.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast
```

### With Verification
```bash
forge script script/02_DeployHook.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast -vvv
```

## What This Script Does

### 1. Load Prerequisites
- Loads the PoolManager address from environment variables
- Validates the PoolManager contract exists and is accessible

### 2. Calculate Hook Address
The script calculates a valid hook address that satisfies Uniswap V4's requirements:
- **Address Encoding**: In Uniswap V4, hook addresses must encode their permissions in the address itself
- **Permission Flags**: The address must have the required permission bits set:
  - `AFTER_INITIALIZE_FLAG`: Called after pool initialization
  - `AFTER_ADD_LIQUIDITY_FLAG`: Called after liquidity addition
  - `AFTER_REMOVE_LIQUIDITY_FLAG`: Called after liquidity removal  
  - `AFTER_SWAP_FLAG`: Called after swaps

### 3. Deploy Hook Contract
- Deploys `YieldMaximizerHook` to the calculated address using `deployCodeTo`
- Passes the PoolManager address as constructor parameter
- Ensures the hook is deployed to an address with correct permission encoding

### 4. Verification
The script verifies the deployment by checking:
- Hook contract bytecode exists at the target address
- Hook returns correct permissions via `getHookPermissions()`
- All required permission flags are enabled

### 5. Save Deployment Info
Creates `deployments/hook.env` with:
```bash
HOOK_ADDRESS=0x...
POOL_MANAGER=0x..
PERMISSIONS=385  # Combined permission flags
DEPLOYER=0x..
DEPLOYMENT_BLOCK=5
DEPLOYMENT_TIMESTAMP=17572...
```

## Hook Permissions Explained

The YieldMaximizerHook requires these permissions:

1. **AFTER_INITIALIZE**: Sets up initial pool strategy tracking when pools are created
2. **AFTER_ADD_LIQUIDITY**: Records liquidity deposits and initializes user strategies
3. **AFTER_REMOVE_LIQUIDITY**: Updates strategy accounting when liquidity is removed
4. **AFTER_SWAP**: Collects fees and triggers compounding when conditions are met
