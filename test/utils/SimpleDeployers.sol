// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/**
 * Proper Deployer Contract for YieldMaximizerHook Testing
 * Following v4-template best practices
 */
contract SimpleDeployers is Test {
    using PoolIdLibrary for PoolKey;

    IPoolManager public poolManager;

    function deployArtifacts() internal {
        // Deploy the full V4 stack properly
        poolManager = new PoolManager(address(this));
        vm.label(address(poolManager), "PoolManager");
    }

    function deployToken(string memory name, string memory symbol) internal returns (MockERC20 token) {
        token = new MockERC20(name, symbol, 18);
        token.mint(address(this), 10_000_000 ether);
        vm.label(address(token), symbol);
    }

    function deployCurrencyPair() internal returns (Currency currency0, Currency currency1) {
        MockERC20 token0 = deployToken("Token0", "T0");
        MockERC20 token1 = deployToken("Token1", "T1");

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        vm.label(address(token0), "Currency0");
        vm.label(address(token1), "Currency1");
    }

    function deployHookToProperAddress(string memory contractName, bytes memory constructorArgs, uint160 permissions)
        internal
        returns (address hookAddress)
    {
        // Calculate the proper hook address based on permissions
        // Following v4-template pattern with namespace to avoid collisions
        hookAddress = address(
            uint160(permissions) ^ (0x4444 << 144) // Namespace to avoid collisions
        );

        // Deploy using forge's deployCodeTo - this is the proper way
        deployCodeTo(contractName, constructorArgs, hookAddress);
        vm.label(hookAddress, "Hook");

        return hookAddress;
    }

    function createPool(
        Currency currency0,
        Currency currency1,
        IHooks hooks,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal returns (PoolKey memory poolKey, PoolId poolId) {
        poolKey =
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});

        poolId = poolKey.toId();
        poolManager.initialize(poolKey, sqrtPriceX96);

        return (poolKey, poolId);
    }
}
