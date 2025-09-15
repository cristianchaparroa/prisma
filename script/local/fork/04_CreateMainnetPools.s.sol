// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract CreateMainnetPools is Script {
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

        pools[2] = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN_DAI")),
            currency1: Currency.wrap(vm.envAddress("TOKEN_USDC")),
            fee: 3000, // Change from 500 to 3000
            tickSpacing: 60, // Change from 10 to 60
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

        // Initialize all pools with market prices
        initializePool(poolManager, pools[0], 79228162514264337593543950336); // ~$3000 ETH
        initializePool(poolManager, pools[1], 79228162514264337593543950336); // ~$3000 ETH
        initializePool(poolManager, pools[2], 79228162514264337593543950336); // correct for 1:1
        initializePool(poolManager, pools[3], 158456325028528675187087900672); // ~$60K BTC

        vm.stopBroadcast();

        console2.log("All mainnet pools created and initialized");
    }

    function initializePool(PoolManager poolManager, PoolKey memory poolKey, uint160 sqrtPriceX96) internal {
        try poolManager.initialize(poolKey, sqrtPriceX96) returns (int24 tick) {
            console2.log("Pool initialized successfully");
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
            console2.log("Tick:", vm.toString(tick));
        } catch Error(string memory reason) {
            console2.log("Pool initialization failed");
            console2.log("Reason:", reason);
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
        } catch (bytes memory) {
            console2.log("Pool initialization failed with unknown error");
            console2.log("Currency0:", vm.toString(Currency.unwrap(poolKey.currency0)));
            console2.log("Currency1:", vm.toString(Currency.unwrap(poolKey.currency1)));
        }
    }
}
