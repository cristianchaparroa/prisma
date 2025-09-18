// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

interface IYieldMaximizerHook {
    function activateStrategy(PoolId poolId, uint256 gasThreshold, uint8 riskLevel) external;
    function getUserStrategy(address user)
        external
        view
        returns (
            bool isActive,
            uint256 totalDeposited,
            uint256 totalCompounded,
            uint256 lastCompoundTime,
            uint256 gasThreshold,
            uint8 riskLevel
        );
    function getPoolStrategy(PoolId poolId)
        external
        view
        returns (uint256 totalUsers, uint256 totalTvl, uint256 lastCompoundTime, bool isActive);
}

contract EnableStrategiesFixed is Script {
    using PoolIdLibrary for PoolKey;

    struct StrategyConfig {
        uint256 gasThreshold;
        uint8 riskLevel;
        string description;
    }

    function run() external {
        IYieldMaximizerHook hook = IYieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));

        address[9] memory testAccounts = [
            vm.envAddress("ACCOUNT_1_ADDRESS"),
            vm.envAddress("ACCOUNT_2_ADDRESS"),
            vm.envAddress("ACCOUNT_3_ADDRESS"),
            vm.envAddress("ACCOUNT_4_ADDRESS"),
            vm.envAddress("ACCOUNT_5_ADDRESS"),
            vm.envAddress("ACCOUNT_6_ADDRESS"),
            vm.envAddress("ACCOUNT_7_ADDRESS"),
            vm.envAddress("ACCOUNT_8_ADDRESS"),
            vm.envAddress("ACCOUNT_9_ADDRESS")
        ];

        uint256[9] memory privateKeys = [
            vm.envUint("ACCOUNT_1_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_2_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_3_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_4_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_5_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_6_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_7_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_8_PRIVATE_KEY"),
            vm.envUint("ACCOUNT_9_PRIVATE_KEY")
        ];

        // Strategy configurations
        StrategyConfig[5] memory strategyConfigs = [
            StrategyConfig(30 gwei, 2, "Conservative"),
            StrategyConfig(50 gwei, 5, "Balanced"),
            StrategyConfig(80 gwei, 8, "Aggressive"),
            StrategyConfig(100 gwei, 10, "Premium"),
            StrategyConfig(20 gwei, 4, "Gas Efficient")
        ];

        // Just use the first pool for activation since the contract only supports one global strategy per user
        PoolKey memory firstPool = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_USDC")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_WETH")),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(vm.envAddress("HOOK_ADDRESS"))
        });

        PoolId poolId = firstPool.toId();

        console2.log("=== Enabling ONE Strategy Per User (Global) ===");
        console2.log("Hook Address:", vm.envAddress("HOOK_ADDRESS"));
        console2.log("Total Users:", testAccounts.length);
        console2.log("Note: Each user gets ONE global strategy that works across all pools");

        for (uint256 i = 0; i < testAccounts.length; i++) {
            address user = testAccounts[i];
            uint256 userPrivateKey = privateKeys[i];

            uint256 configIndex = i % strategyConfigs.length;
            StrategyConfig memory config = strategyConfigs[configIndex];

            console2.log("\n--- Configuring User", i + 1, "---");
            console2.log("Address:", user);
            console2.log("Strategy:", config.description);
            console2.log("Gas Threshold:", vm.toString(config.gasThreshold));
            console2.log("Risk Level:", vm.toString(config.riskLevel));

            // Check if user already has an active strategy
            try hook.getUserStrategy(user) returns (bool isActive, uint256, uint256, uint256, uint256, uint8) {
                if (isActive) {
                    console2.log("User already has active strategy, skipping");
                    continue;
                }
            } catch {
                // Continue if we can't read strategy
            }

            vm.startBroadcast(userPrivateKey);

            try hook.activateStrategy(poolId, config.gasThreshold, config.riskLevel) {
                console2.log("Global strategy activated successfully");

                // Verify
                (
                    bool isActive,
                    uint256 totalDeposited,
                    uint256 totalCompounded,
                    uint256 lastCompoundTime,
                    uint256 gasThreshold,
                    uint8 riskLevel
                ) = hook.getUserStrategy(user);

                // Suppress unused variable warnings
                totalDeposited;
                totalCompounded;
                lastCompoundTime;

                if (isActive && gasThreshold == config.gasThreshold && riskLevel == config.riskLevel) {
                    console2.log("Strategy verified");
                } else {
                    console2.log("Strategy verification failed");
                }
            } catch Error(string memory reason) {
                console2.log("Failed:", reason);
            } catch {
                console2.log("Failed: Unknown error");
            }

            vm.stopBroadcast();
        }

        console2.log("\n=== Final Summary ===");

        uint256 totalActive = 0;
        for (uint256 i = 0; i < testAccounts.length; i++) {
            try hook.getUserStrategy(testAccounts[i]) returns (
                bool isActive, uint256, uint256, uint256, uint256 gasThreshold, uint8 riskLevel
            ) {
                if (isActive) {
                    totalActive++;
                    console2.log("User", i + 1, "- Active");
                    console2.log("  Risk Level:", vm.toString(riskLevel));
                    console2.log("  Gas Threshold:", vm.toString(gasThreshold));
                }
            } catch {
                console2.log("User", i + 1, "- Error reading strategy");
            }
        }

        console2.log("Total Active Strategies:", totalActive);
        console2.log("Success Rate:", (totalActive * 100) / testAccounts.length, "%");
    }
}
