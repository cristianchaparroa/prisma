// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "./01_CreateTokens.s.sol";

/**
 * @title Distribute Tokens to Test Accounts
 * @notice Distributes tokens to test accounts using deployed token addresses
 */
contract DistributeTokens is Script {
    // Token contracts (loaded from environment variables)
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;
    MockERC20 public yieldToken;

    // Test accounts from .env file
    address[] public testAccounts;

    // Distribution amounts per account
    struct DistributionAmounts {
        uint256 weth; // WETH amount (18 decimals)
        uint256 usdc; // USDC amount (6 decimals)
        uint256 dai; // DAI amount (18 decimals)
        uint256 wbtc; // WBTC amount (8 decimals)
        uint256 yield; // YIELD amount (18 decimals)
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Distributing tokens to test accounts...");

        // Load token contracts from environment variables
        _loadTokenContracts();

        // Load test accounts from environment
        _loadTestAccounts();

        // Define distribution amounts for different user types
        DistributionAmounts memory smallUser = DistributionAmounts({
            weth: 10 * 10 ** 18, // 10 WETH
            usdc: 25000 * 10 ** 6, // 25,000 USDC
            dai: 25000 * 10 ** 18, // 25,000 DAI
            wbtc: 1 * 10 ** 8, // 1 WBTC
            yield: 10000 * 10 ** 18 // 10,000 YIELD
        });

        DistributionAmounts memory mediumUser = DistributionAmounts({
            weth: 50 * 10 ** 18, // 50 WETH
            usdc: 125000 * 10 ** 6, // 125,000 USDC
            dai: 125000 * 10 ** 18, // 125,000 DAI
            wbtc: 5 * 10 ** 8, // 5 WBTC
            yield: 50000 * 10 ** 18 // 50,000 YIELD
        });

        DistributionAmounts memory largeUser = DistributionAmounts({
            weth: 200 * 10 ** 18, // 200 WETH
            usdc: 500000 * 10 ** 6, // 500,000 USDC
            dai: 500000 * 10 ** 18, // 500,000 DAI
            wbtc: 20 * 10 ** 8, // 20 WBTC
            yield: 200000 * 10 ** 18 // 200,000 YIELD
        });

        // Distribute to accounts (skip account 0 as it's the deployer)
        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            address account = testAccounts[i];

            DistributionAmounts memory amounts;
            if (i <= 6) {
                amounts = smallUser; // Accounts 1-6: Small users
            } else if (i <= 8) {
                amounts = mediumUser; // Accounts 7-8: Medium users
            } else {
                amounts = largeUser; // Account 9: Large user
            }

            _distributeToAccount(account, amounts, i);
        }

        console.log("\n=== TOKEN DISTRIBUTION COMPLETE ===");
        console.log("Small users (accounts 1-6): 10 WETH, 25K USDC/DAI, 1 WBTC, 10K YIELD");
        console.log("Medium users (accounts 7-8): 50 WETH, 125K USDC/DAI, 5 WBTC, 50K YIELD");
        console.log("Large user (account 9): 200 WETH, 500K USDC/DAI, 20 WBTC, 200K YIELD");

        vm.stopBroadcast();

        // Save distribution info
        _saveDistributionInfo();
    }

    function _loadTokenContracts() internal {
        console.log("Loading token contracts from deployment addresses...");

        // Note: You need to manually set these in .env after running 01_CreateTokens.s.sol
        // Or run setTokenAddresses() with the deployed addresses

        console.log("⚠️  Token addresses need to be set manually for now");
        console.log("After running 01_CreateTokens.s.sol, copy the addresses and either:");
        console.log("1. Add them to .env file as WETH_ADDRESS=0x..., etc.");
        console.log("2. Call setTokenAddresses() with the deployed addresses");

        // For now, we'll expect these to be set in environment
        // In a complete implementation, you'd parse the deployments/tokens.env file
    }

    function _loadTestAccounts() internal {
        console.log("Loading test accounts from .env file...");

        // Load accounts from environment variables
        testAccounts.push(vm.envAddress("ANVIL_ADDRESS")); // Account 0 (deployer)
        testAccounts.push(vm.envAddress("ACCOUNT_1_ADDRESS")); // Account 1
        testAccounts.push(vm.envAddress("ACCOUNT_2_ADDRESS")); // Account 2
        testAccounts.push(vm.envAddress("ACCOUNT_3_ADDRESS")); // Account 3

        // Add more accounts if they exist in .env
        try vm.envAddress("ACCOUNT_4_ADDRESS") returns (address addr) {
            testAccounts.push(addr);
        } catch {
            // Account 4 not set, that's ok
        }

        console.log("✅ Loaded", testAccounts.length, "test accounts");
        for (uint256 i = 0; i < testAccounts.length; i++) {
            console.log("  Account", i, ":", testAccounts[i]);
        }
    }

    function _distributeToAccount(address account, DistributionAmounts memory amounts, uint256 accountIndex) internal {
        console.log("\nDistributing to account", accountIndex, ":", account);

        // Transfer tokens to account
        weth.transfer(account, amounts.weth);
        usdc.transfer(account, amounts.usdc);
        dai.transfer(account, amounts.dai);
        wbtc.transfer(account, amounts.wbtc);
        yieldToken.transfer(account, amounts.yield);

        console.log("  WETH:", amounts.weth / 10 ** 18);
        console.log("  USDC:", amounts.usdc / 10 ** 6);
        console.log("  DAI:", amounts.dai / 10 ** 18);
        console.log("  WBTC:", amounts.wbtc / 10 ** 8);
        console.log("  YIELD:", amounts.yield / 10 ** 18);
    }

    function _saveDistributionInfo() internal {
        string memory distributionInfo = "# Token Distribution Info\n";
        distributionInfo =
            string.concat(distributionInfo, "TOTAL_TEST_ACCOUNTS=", vm.toString(testAccounts.length), "\n");
        distributionInfo = string.concat(distributionInfo, "SMALL_USERS=6\n");
        distributionInfo = string.concat(distributionInfo, "MEDIUM_USERS=2\n");
        distributionInfo = string.concat(distributionInfo, "LARGE_USERS=1\n");

        // Add account addresses
        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            distributionInfo =
                string.concat(distributionInfo, "ACCOUNT_", vm.toString(i), "=", vm.toString(testAccounts[i]), "\n");
        }

        vm.writeFile("./deployments/distribution.env", distributionInfo);
        console.log("\nDistribution info saved to: ./deployments/distribution.env");
    }

    // Helper function to set token addresses manually
    function setTokenAddresses(address _weth, address _usdc, address _dai, address _wbtc, address _yield) external {
        weth = MockERC20(_weth);
        usdc = MockERC20(_usdc);
        dai = MockERC20(_dai);
        wbtc = MockERC20(_wbtc);
        yieldToken = MockERC20(_yield);

        console.log("✅ Token addresses set:");
        console.log("  WETH:", address(weth));
        console.log("  USDC:", address(usdc));
        console.log("  DAI:", address(dai));
        console.log("  WBTC:", address(wbtc));
        console.log("  YIELD:", address(yieldToken));
    }
}
