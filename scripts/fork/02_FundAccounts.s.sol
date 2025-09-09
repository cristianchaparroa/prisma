// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title Fund Test Accounts with Real Mainnet Tokens
 * @notice Transfers real tokens from whale addresses to test accounts
 * @dev Replaces 05_DistributeTokens.s.sol for mainnet fork environment
 */
contract FundAccounts is Script {
    // Real mainnet tokens
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;

    // Whale addresses with large token holdings
    address public usdcWhale;
    address public wethWhale;
    address public daiWhale;
    address public wbtcWhale;

    // Test accounts
    address[] public testAccounts;

    struct FundingAmounts {
        uint256 weth;  // 18 decimals
        uint256 usdc;  // 6 decimals
        uint256 dai;   // 18 decimals
        uint256 wbtc;  // 8 decimals
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        console.log("Funding test accounts with real mainnet tokens...");

        // Load contracts and whales
        _loadContracts();
        _loadTestAccounts();

        // Define funding amounts per user type
        FundingAmounts memory smallUser = FundingAmounts({
            weth: 20 * 10**18,      // 20 WETH (~$50K)
            usdc: 50_000 * 10**6,   // 50K USDC
            dai: 50_000 * 10**18,   // 50K DAI
            wbtc: 1 * 10**8         // 1 WBTC (~$60K)
        });

        FundingAmounts memory mediumUser = FundingAmounts({
            weth: 100 * 10**18,     // 100 WETH (~$250K)
            usdc: 250_000 * 10**6,  // 250K USDC
            dai: 250_000 * 10**18,  // 250K DAI
            wbtc: 5 * 10**8         // 5 WBTC (~$300K)
        });

        FundingAmounts memory largeUser = FundingAmounts({
            weth: 500 * 10**18,     // 500 WETH (~$1.25M)
            usdc: 1_000_000 * 10**6, // 1M USDC
            dai: 1_000_000 * 10**18, // 1M DAI
            wbtc: 20 * 10**8        // 20 WBTC (~$1.2M)
        });

        // Fund accounts (skip deployer account 0)
        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            FundingAmounts memory amounts;

            if (i <= 6) {
                amounts = smallUser;    // Accounts 1-6: Small users
            } else if (i <= 8) {
                amounts = mediumUser;   // Accounts 7-8: Medium users
            } else {
                amounts = largeUser;    // Account 9: Large whale user
            }

            _fundAccount(testAccounts[i], amounts, i);
        }

        console.log("\nAll test accounts funded with real mainnet tokens");
        _saveFundingInfo();
    }

    function _loadContracts() internal {
        // Load real mainnet token contracts
        weth = IERC20(vm.envAddress("TOKEN_WETH"));
        usdc = IERC20(vm.envAddress("TOKEN_USDC"));
        dai = IERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = IERC20(vm.envAddress("TOKEN_WBTC"));

        // Load whale addresses
        usdcWhale = vm.envAddress("USDC_WHALE");
        wethWhale = vm.envAddress("WETH_WHALE");
        daiWhale = vm.envAddress("DAI_WHALE");
        wbtcWhale = vm.envAddress("WBTC_WHALE");

        console.log("Loaded token contracts:");
        console.log("  WETH:", address(weth));
        console.log("  USDC:", address(usdc));
        console.log("  DAI:", address(dai));
        console.log("  WBTC:", address(wbtc));
    }

    function _loadTestAccounts() internal {
        // Load test accounts from environment
        testAccounts.push(vm.envAddress("ANVIL_ADDRESS"));      // Account 0
        testAccounts.push(vm.envAddress("ACCOUNT_1_ADDRESS"));  // Account 1
        testAccounts.push(vm.envAddress("ACCOUNT_2_ADDRESS"));  // Account 2
        testAccounts.push(vm.envAddress("ACCOUNT_3_ADDRESS"));  // Account 3
        testAccounts.push(vm.envAddress("ACCOUNT_4_ADDRESS"));  // Account 4
        testAccounts.push(vm.envAddress("ACCOUNT_5_ADDRESS"));  // Account 5
        testAccounts.push(vm.envAddress("ACCOUNT_6_ADDRESS"));  // Account 6
        testAccounts.push(vm.envAddress("ACCOUNT_7_ADDRESS"));  // Account 7
        testAccounts.push(vm.envAddress("ACCOUNT_8_ADDRESS"));  // Account 8
        testAccounts.push(vm.envAddress("ACCOUNT_9_ADDRESS"));  // Account 9

        console.log("Loaded", testAccounts.length, "test accounts");
    }

    function _fundAccount(address account, FundingAmounts memory amounts, uint256 accountIndex) internal {
        console.log("\nFunding account", accountIndex, ":", account);

        // Transfer WETH from whale
        vm.startPrank(wethWhale);
        weth.transfer(account, amounts.weth);
        vm.stopPrank();

        // Transfer USDC from whale
        vm.startPrank(usdcWhale);
        usdc.transfer(account, amounts.usdc);
        vm.stopPrank();

        // Transfer DAI from whale
        vm.startPrank(daiWhale);
        dai.transfer(account, amounts.dai);
        vm.stopPrank();

        // Transfer WBTC from whale
        vm.startPrank(wbtcWhale);
        wbtc.transfer(account, amounts.wbtc);
        vm.stopPrank();

        console.log("WETH:", amounts.weth / 10**18);
        console.log("USDC:", amounts.usdc / 10**6);
        console.log("DAI:", amounts.dai / 10**18);
        console.log("WBTC:", amounts.wbtc / 10**8);

        // Verify balances
        require(weth.balanceOf(account) >= amounts.weth, "WETH transfer failed");
        require(usdc.balanceOf(account) >= amounts.usdc, "USDC transfer failed");
        require(dai.balanceOf(account) >= amounts.dai, "DAI transfer failed");
        require(wbtc.balanceOf(account) >= amounts.wbtc, "WBTC transfer failed");
    }

    function _saveFundingInfo() internal {
        string memory fundingInfo = "# Real Token Funding Results\n";
        fundingInfo = string.concat(fundingInfo, "FUNDING_METHOD=whale_transfers\n");
        fundingInfo = string.concat(fundingInfo, "TOTAL_FUNDED_ACCOUNTS=", vm.toString(testAccounts.length - 1), "\n");
        fundingInfo = string.concat(fundingInfo, "SMALL_USERS=6\n");
        fundingInfo = string.concat(fundingInfo, "MEDIUM_USERS=2\n");
        fundingInfo = string.concat(fundingInfo, "LARGE_USERS=1\n");
        fundingInfo = string.concat(fundingInfo, "FUNDING_TIMESTAMP=", vm.toString(block.timestamp), "\n");

        vm.writeFile("./deployments/fork-funding.env", fundingInfo);
        console.log("Funding info saved to: ./deployments/fork-funding.env");
    }
}
