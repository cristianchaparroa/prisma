# Quick Start: Deploy Uniswap V4 Infrastructure

## Prerequisites

1. **Start Anvil local node**:
```bash
# Terminal 1 - Keep this running
anvil --port 8545 --chain-id 31337 --accounts 10 --balance 10000
```

2. **Setup environment**:
```bash
# Create .env file
echo "ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" > .env
echo "ANVIL_RPC_URL=http://localhost:8545" >> .env
```

## Deploy Infrastructure

```bash
# Execute the deployment script
forge script script/00_DeployV4Infrastructure.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast -vvv
```

## Expected Output

```
== Logs ==
  Deploying Uniswap V4 Infrastructure...
  Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  Chain ID: 31337
  PoolManager deployed at: 0x[ADDRESS]
  Controller gas limit: 500000

  === UNISWAP V4 INFRASTRUCTURE DEPLOYED ===
  PoolManager: 0x[ADDRESS]
  Ready for hook integration!
```

## What This Creates

- ✅ **PoolManager**: Core Uniswap V4 contract deployed
- ✅ **deployments/v4-infrastructure.env**: Saves deployment addresses
- ✅ **Ready for next step**: Token creation
