// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MockERC20} from "./01_CreateTokens.s.sol";

/**
 * @title Create Hook-Enabled Liquidity Pools
 * @notice Creates Uniswap V4 pools with YieldMaximizerHook integrated from the start
 */
contract CreatePools is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts
    IPoolManager public poolManager;
    IHooks public hook;

    // Token contracts
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;
    MockERC20 public yieldToken;

    // Helper struct for currency sorting
    struct CurrencyPair {
        Currency currency0;
        Currency currency1;
    }

    // Pool configurations
    struct PoolConfig {
        string name;
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        uint160 sqrtPriceX96;
    }

    // Storage for created pools
    PoolKey[] public poolKeys;
    PoolId[] public poolIds;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Creating Uniswap V4 liquidity pools...");

        // Load contracts
        _loadContracts();

        // Create pool configurations
        PoolConfig[] memory configs = _createPoolConfigs();

        // Create all pools
        for (uint256 i = 0; i < configs.length; i++) {
            _createPool(configs[i]);
        }

        console.log("\n=== POOL CREATION COMPLETE ===");
        console.log("Total pools created:", poolKeys.length);

        vm.stopBroadcast();

        // Save pool information
        _savePoolInfo();
    }

    function _loadContracts() internal {
        console.log("Loading contracts from environment variables...");

        // Load PoolManager from environment variable
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        poolManager = IPoolManager(poolManagerAddr);
        console.log("PoolManager loaded:", address(poolManager));

        // Load YieldMaximizerHook from environment variable
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        hook = IHooks(hookAddr);
        console.log("YieldMaximizerHook loaded:", address(hook));

        // Load token contracts from environment variables
        weth = MockERC20(vm.envAddress("TOKEN_WETH"));
        usdc = MockERC20(vm.envAddress("TOKEN_USDC"));
        dai = MockERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = MockERC20(vm.envAddress("TOKEN_WBTC"));
        yieldToken = MockERC20(vm.envAddress("TOKEN_YIELD"));

        console.log("Tokens loaded:");
        console.log("  WETH:", address(weth));
        console.log("  USDC:", address(usdc));
        console.log("  DAI:", address(dai));
        console.log("  WBTC:", address(wbtc));
        console.log("  YIELD:", address(yieldToken));
    }

    function _createPoolConfigs() internal view returns (PoolConfig[] memory) {
        console.log("Creating pool configurations...");

        PoolConfig[] memory configs = new PoolConfig[](5);

        // 1. WETH/USDC - High volume pair (0.3% fee)
        configs[0] = PoolConfig({
            name: "WETH/USDC",
            currency0: _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(usdc))).currency0,
            currency1: _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(usdc))).currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(2500, 1) // 1 WETH = 2500 USDC
        });

        // 2. WETH/DAI - Alternative stable pair (0.3% fee)
        configs[1] = PoolConfig({
            name: "WETH/DAI",
            currency0: _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(dai))).currency0,
            currency1: _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(dai))).currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(2500, 1) // 1 WETH = 2500 DAI
        });

        // 3. WBTC/WETH - Crypto-to-crypto pair (0.3% fee)
        configs[2] = PoolConfig({
            name: "WBTC/WETH",
            currency0: _sortCurrencies(Currency.wrap(address(wbtc)), Currency.wrap(address(weth))).currency0,
            currency1: _sortCurrencies(Currency.wrap(address(wbtc)), Currency.wrap(address(weth))).currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(20, 1) // 1 WBTC = 20 WETH (approx $50k BTC)
        });

        // 4. USDC/DAI - Stable-to-stable pair (0.05% fee)
        configs[3] = PoolConfig({
            name: "USDC/DAI",
            currency0: _sortCurrencies(Currency.wrap(address(usdc)), Currency.wrap(address(dai))).currency0,
            currency1: _sortCurrencies(Currency.wrap(address(usdc)), Currency.wrap(address(dai))).currency1,
            fee: 500, // 0.05%
            tickSpacing: 10,
            sqrtPriceX96: _calculateSqrtPriceX96(1, 1) // 1 USDC = 1 DAI
        });

        // 5. YIELD/WETH - Protocol token pair (1% fee)
        configs[4] = PoolConfig({
            name: "YIELD/WETH",
            currency0: _sortCurrencies(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth))).currency0,
            currency1: _sortCurrencies(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth))).currency1,
            fee: 10000, // 1%
            tickSpacing: 200,
            sqrtPriceX96: _calculateSqrtPriceX96(100, 1) // 100 YIELD = 1 WETH
        });

        return configs;
    }

    function _createPool(PoolConfig memory config) internal {
        console.log("\nCreating pool:", config.name);
        console.log("  Currency0:", Currency.unwrap(config.currency0));
        console.log("  Currency1:", Currency.unwrap(config.currency1));
        console.log("  Fee:", config.fee);
        console.log("  Tick Spacing:", config.tickSpacing);
        console.log("  Hook:", address(hook));

        // Create PoolKey with YieldMaximizerHook
        PoolKey memory key = PoolKey({
            currency0: config.currency0,
            currency1: config.currency1,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: hook // YieldMaximizerHook integrated from creation
        });

        // Initialize the pool with error checking
        console.log("Initializing pool...");
        try poolManager.initialize(key, config.sqrtPriceX96) {
            console.log("  Pool initialized successfully");
        } catch Error(string memory reason) {
            console.log("  Pool initialization failed:", reason);
            revert(string.concat("Failed to initialize pool: ", reason));
        } catch {
            console.log("  Pool initialization failed: Unknown error");
            revert("Failed to initialize pool: Unknown error");
        }

        // Store pool info
        poolKeys.push(key);
        PoolId poolId = key.toId();
        poolIds.push(poolId);

        console.log("  Pool creation completed");
        console.log("    Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        console.log("Hook-enabled pool created with ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("  Hook address in pool:", address(key.hooks));
    }

    function _sortCurrencies(Currency currencyA, Currency currencyB) internal pure returns (CurrencyPair memory) {
        if (Currency.unwrap(currencyA) < Currency.unwrap(currencyB)) {
            return CurrencyPair(currencyA, currencyB);
        } else {
            return CurrencyPair(currencyB, currencyA);
        }
    }

    function _calculateSqrtPriceX96(uint256 price0, uint256 price1) internal pure returns (uint160) {
        // Calculate sqrt(price) * 2^96
        // price = price0/price1 (how many of token1 per token0)
        // This is a simplified calculation - in production use proper math libraries

        uint256 ratioX96 = (price0 * (2 ** 96)) / price1;
        uint160 sqrtPriceX96 = uint160(_sqrt(ratioX96));

        return sqrtPriceX96;
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function _savePoolInfo() internal {
        console.log("Saving pool information...");

        string memory poolInfo = "# Created Pool Information\n";
        poolInfo = string.concat(poolInfo, "TOTAL_POOLS=", vm.toString(poolKeys.length), "\n\n");

        for (uint256 i = 0; i < poolKeys.length; i++) {
            PoolKey memory key = poolKeys[i];
            PoolId poolId = poolIds[i];

            poolInfo =
                string.concat(poolInfo, "POOL_", vm.toString(i), "_ID=", vm.toString(PoolId.unwrap(poolId)), "\n");
            poolInfo = string.concat(
                poolInfo, "POOL_", vm.toString(i), "_CURRENCY0=", vm.toString(Currency.unwrap(key.currency0)), "\n"
            );
            poolInfo = string.concat(
                poolInfo, "POOL_", vm.toString(i), "_CURRENCY1=", vm.toString(Currency.unwrap(key.currency1)), "\n"
            );
            poolInfo = string.concat(poolInfo, "POOL_", vm.toString(i), "_FEE=", vm.toString(key.fee), "\n");
            poolInfo = string.concat(poolInfo, "\n");
        }

        vm.writeFile("./deployments/pools.env", poolInfo);
        console.log("Pool info saved to: ./deployments/pools.env");
    }

    // Helper function to get created pools
    function getPoolKeys() external view returns (PoolKey[] memory) {
        return poolKeys;
    }

    function getPoolIds() external view returns (PoolId[] memory) {
        return poolIds;
    }

    function getPoolInfo(uint256 index) external view returns (PoolKey memory key, PoolId poolId) {
        require(index < poolKeys.length, "Pool index out of bounds");
        return (poolKeys[index], poolIds[index]);
    }
}
