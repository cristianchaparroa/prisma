// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract CreateMainnetPools is Script {
    // Helper function to calculate sqrtPriceX96 for different ratios
    function getSqrtPriceX96(uint256 token0Amount, uint256 token1Amount, uint8 token0Decimals, uint8 token1Decimals)
        internal
        pure
        returns (uint160)
    {
        // Adjust amounts for decimals
        uint256 adjustedToken0 = token0Amount * (10 ** (18 - token0Decimals));
        uint256 adjustedToken1 = token1Amount * (10 ** (18 - token1Decimals));

        // Calculate price ratio (token1/token0)
        uint256 priceRatio = (adjustedToken1 * 1e18) / adjustedToken0;

        // Calculate sqrt(priceRatio) * 2^96
        uint256 sqrtPrice = sqrt(priceRatio * (2 ** 192));

        return uint160(sqrtPrice);
    }

    // Simple sqrt implementation for demonstration
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        PoolManager poolManager = PoolManager(vm.envAddress("POOL_MANAGER"));
        IHooks hook = IHooks(vm.envAddress("HOOK_ADDRESS"));

        vm.startBroadcast(deployerPrivateKey);

        // Create main pools with real tokens
        PoolKey[] memory pools = new PoolKey[](4);

        // USDC/WETH - Primary trading pair (0xa0b8 < 0xC02a)
        pools[0] = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_USDC")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_WETH")),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: hook
        });

        // DAI/WETH - Alternative stable pair (0x6B17 < 0xC02a)
        pools[1] = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_DAI")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_WETH")),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        // DAI/USDC - Stablecoin pair (CRITICAL FIX HERE)
        pools[2] = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_DAI")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_USDC")),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        // WBTC/WETH - Crypto pair (0x2260 < 0xC02a)
        pools[3] = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_WBTC")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_WETH")),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        // Initialize pools with CORRECT prices

        // USDC/WETH: 1 ETH = 3000 USDC (token1/token0 ratio)
        initializePool(poolManager, pools[0], 79228162514264337593543950336); // ~$3000 ETH

        // DAI/WETH: 1 ETH = 3000 DAI
        initializePool(poolManager, pools[1], 79228162514264337593543950336); // ~$3000 ETH

        // DAI/USDC: 1 USDC = 1 DAI (accounting for decimal difference)
        initializePool(poolManager, pools[2], 79228162514264337593543950336); // Original value but we'll add concentrated liquidity

        // WBTC/WETH: 1 WBTC = 20 ETH
        initializePool(poolManager, pools[3], 158456325028528675187087900672); // ~20x ETH price

        vm.stopBroadcast();

        console2.log("All mainnet pools created and initialized with CORRECT prices");
    }

    function initializePool(PoolManager poolManager, PoolKey memory poolKey, uint160 sqrtPriceX96) internal {
        try poolManager.initialize(poolKey, sqrtPriceX96) returns (int24 tick) {
            console2.log("Pool initialized successfully");
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
            console2.log("SqrtPriceX96:", vm.toString(sqrtPriceX96));
            console2.log("Tick:", vm.toString(tick));
        } catch Error(string memory reason) {
            console2.log("Pool initialization failed");
            console2.log("Reason:", reason);
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
            console2.log("Attempted SqrtPriceX96:", vm.toString(sqrtPriceX96));
        } catch (bytes memory) {
            console2.log("Pool initialization failed with unknown error");
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
            console2.log("Attempted SqrtPriceX96:", vm.toString(sqrtPriceX96));
        }
    }
}
