# Create Test Tokens Script

## Overview
Creates 5 test tokens (WETH, USDC, DAI, WBTC, YIELD) with large initial supplies for testing the Yield Maximizer system.

## Prerequisites

1. **Anvil running** with infrastructure deployed:
```bash
./scripts/local/setup-anvil.sh  # If not already running
```

2. **Environment sourced**:
```bash
source .env
```

## Execute Token Creation

```bash
forge script script/01_CreateTokens.s.sol:CreateTokens \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v
```

## What Gets Created

| Token | Symbol | Decimals | Initial Supply | Purpose |
|-------|--------|----------|----------------|---------|
| Wrapped Ether | WETH | 18 | 10,000 | Primary base token |
| USD Coin | USDC | 6 | 10,000,000 | Stable coin for pairs |
| Dai Stablecoin | DAI | 18 | 10,000,000 | Additional stable coin |
| Wrapped Bitcoin | WBTC | 8 | 1,000 | Diversified pairs |
| Yield Token | YIELD | 18 | 100,000,000 | Protocol governance token |

## Expected Output

```
== Logs ==
  Creating test tokens...
  Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  Deployed WETH at: 0x[ADDRESS]
    Initial supply: 10000 WETH
  Deployed USDC at: 0x[ADDRESS]
    Initial supply: 10000000 USDC
  ...

=== TOKEN DEPLOYMENT COMPLETE ===
  WETH : 0x[ADDRESS]
    Balance: 10000 WETH
  USDC : 0x[ADDRESS]
    Balance: 10000000 USDC
  ...

Token addresses saved to: ./deployments/tokens.env
```

## Generated Files

- **`deployments/tokens.env`**: Token contract addresses for other scripts
- **Contract deployments**: All tokens deployed to Anvil

## Features

### MockERC20 Contract
- **Minting**: Owner can mint new tokens
- **Burning**: Owner can burn tokens
- **Faucet**: Anyone can get up to 1,000 tokens (testing helper)

### Token Allocation
All initial supply goes to the deployer (Account 0), ready for:
- Liquidity provision
- Distribution to test accounts
- Pool creation

## Next Steps

After successful token creation:

1. **Distribute tokens** to test accounts:
```bash
forge script script/02_DistributeTokens.s.sol --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast -v
```

2. **Create liquidity pools** with these tokens

3. **Test the yield maximizer** with realistic token amounts

## Troubleshooting

**Script fails with "insufficient funds":**
- Ensure Anvil is running with funded accounts
- Check that `ANVIL_PRIVATE_KEY` is set correctly

**Token deployment fails:**
- Verify Solidity version (0.8.26) in foundry.toml
- Check that all dependencies are installed: `forge install`

**File write permission error:**
- Ensure `fs_permissions` is set in foundry.toml
- Check that `deployments/` directory exists

## Token Contract Interface

```solidity
interface IERC20Extended {
    // Standard ERC20
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    
    // Extended functionality
    function mint(address to, uint256 amount) external; // Owner only
    function burn(address from, uint256 amount) external; // Owner only
    function faucet(uint256 amount) external; // Anyone, max 1000 tokens
}
```

## Gas Usage

- **Per token deployment**: ~800,000 gas
- **Total deployment**: ~4,000,000 gas
- **Cost on Anvil**: ~0.004 ETH total

---

*Ready to create liquidity pools and start testing the auto-compounder!*