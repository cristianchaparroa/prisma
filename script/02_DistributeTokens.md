# Distribute Test Tokens Script

## Overview
Distributes the created test tokens (WETH, USDC, DAI, WBTC, YIELD) to multiple test accounts with different allocation tiers to simulate realistic user scenarios.

## Prerequisites

1. **Tokens already created**:
```bash
# Should be done via run-local-env.sh or manually:
forge script script/01_CreateTokens.s.sol:CreateTokens --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast -v
```

2. **Environment properly set**:
```bash
source .env  # Should contain token addresses and test accounts
```

3. **Token addresses in environment** (auto-added by run-local-env.sh):
```bash
# These should be in your .env file:
TOKEN_WETH=0x...
TOKEN_USDC=0x...
TOKEN_DAI=0x...
TOKEN_WBTC=0x...
TOKEN_YIELD=0x...
```

## Execute Token Distribution

```bash
forge script script/02_DistributeTokens.s.sol:DistributeTokens \
    --rpc-url $ANVIL_RPC_URL \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast -v
```

## Distribution Strategy

### User Tiers

| User Type | Accounts | WETH | USDC | DAI | WBTC | YIELD |
|-----------|----------|------|------|-----|------|-------|
| **Small Users** | 1-6 | 10 | 25,000 | 25,000 | 1 | 10,000 |
| **Medium Users** | 7-8 | 50 | 125,000 | 125,000 | 5 | 50,000 |
| **Large User** | 9 | 200 | 500,000 | 500,000 | 20 | 200,000 |

### Account Assignment
- **Account 0**: Deployer (keeps remaining tokens)
- **Accounts 1-6**: Small users (6 accounts)
- **Accounts 7-8**: Medium users (2 accounts)  
- **Account 9**: Large user (1 account)

## Expected Output

```
== Logs ==
  Distributing tokens to test accounts...
  Loading token contracts from deployment addresses...
  Loading test accounts from .env file...
  ✅ Loaded 10 test accounts
    Account 0 : 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
    Account 1 : 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    ...

  Distributing to account 1 : 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    WETH: 10
    USDC: 25000
    DAI: 25000
    WBTC: 1
    YIELD: 10000
  ...

=== TOKEN DISTRIBUTION COMPLETE ===
  Small users (accounts 1-6): 10 WETH, 25K USDC/DAI, 1 WBTC, 10K YIELD
  Medium users (accounts 7-8): 50 WETH, 125K USDC/DAI, 5 WBTC, 50K YIELD
  Large user (account 9): 200 WETH, 500K USDC/DAI, 20 WBTC, 200K YIELD

  Distribution info saved to: ./deployments/distribution.env
```

## Generated Files

- **`deployments/distribution.env`**: Account distribution summary
- **Updated balances**: All test accounts funded with appropriate amounts

## Account Loading

### From Environment Variables
The script loads test accounts from your `.env` file:
```bash
ANVIL_ADDRESS=0xf39...          # Account 0 (deployer)
ACCOUNT_1_ADDRESS=0x7099...     # Account 1
ACCOUNT_2_ADDRESS=0x3C44...     # Account 2
ACCOUNT_3_ADDRESS=0x90F7...     # Account 3
```

### Automatic Detection
- Script automatically detects available accounts
- Gracefully handles missing accounts
- Logs all loaded accounts for verification

## Token Contract Loading

### Automatic Method (Recommended)
If you used `./scripts/local/run-local-env.sh`, token addresses are automatically added to `.env`:
```bash
TOKEN_WETH=0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
TOKEN_USDC=0x0165878A594ca255338adfa4d48449f69242Eb8F
# etc.
```

### Manual Method
If token addresses aren't auto-loaded, use the helper function:
```solidity
// Call this first with your deployed token addresses
setTokenAddresses(
    0x..., // WETH address
    0x..., // USDC address  
    0x..., // DAI address
    0x..., // WBTC address
    0x...  // YIELD address
);
```

## Use Cases Enabled

### Small Users (Accounts 1-6)
- **Purpose**: Regular DeFi users
- **Liquidity**: $50K-75K equivalent
- **Use**: Basic auto-compounding testing

### Medium Users (Accounts 7-8)  
- **Purpose**: Power users / institutions
- **Liquidity**: $250K-375K equivalent
- **Use**: Advanced strategy testing

### Large User (Account 9)
- **Purpose**: Whale / institutional testing
- **Liquidity**: $1M+ equivalent  
- **Use**: High-volume gas optimization testing

## Next Steps

After successful distribution:

1. **Create liquidity pools**:
```bash
forge script script/03_CreatePools.s.sol:CreatePools --rpc-url $ANVIL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast -v
```

2. **Test user interactions** with different account sizes

3. **Verify auto-compounding** with realistic user scenarios

## Troubleshooting

**Error: "Token addresses need to be set manually"**
- Run `./scripts/local/run-local-env.sh` to auto-generate addresses
- Or manually add TOKEN_* addresses to your .env file

**Error: "Account not found"**
- Verify `.env` contains ACCOUNT_N_ADDRESS variables
- Check that Anvil is running with sufficient accounts

**Transfer fails with "insufficient balance"**
- Ensure deployer (Account 0) has enough tokens
- Verify tokens were created successfully in previous step

**Script can't find deployments/tokens.env**
- Run token creation script first
- Check file permissions on deployments folder

## Distribution Summary

```
Total Distribution (excluding deployer):
- WETH: 630 tokens (6.3% of supply)
- USDC: 1,275,000 tokens (12.75% of supply)  
- DAI: 1,275,000 tokens (12.75% of supply)
- WBTC: 51 tokens (5.1% of supply)
- YIELD: 510,000 tokens (0.51% of supply)

Remaining with deployer for:
- Pool creation and seeding
- Additional testing scenarios
- Emergency operations
```

---

*Ready to create pools and test the complete yield maximizer ecosystem!*