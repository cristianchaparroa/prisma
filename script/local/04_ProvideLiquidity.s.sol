// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {MockERC20} from "./01_CreateTokens.s.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title Provide Liquidity to Hook-Enabled Pools
 * @notice Adds liquidity to hook-enabled pools using PositionManager
 */
contract ProvideLiquidity is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IHooks public hook;

    // Token contracts
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;
    MockERC20 public yieldToken;

    // Pool configurations
    struct PoolConfig {
        string name;
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        uint160 sqrtPriceX96;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Providing liquidity using PositionManager...");

        // Load contracts
        _loadContracts();

        // Provide liquidity to each pool
        _provideLiquidityToAllPools();

        console.log("\n=== LIQUIDITY PROVIDED SUCCESSFULLY ===");

        vm.stopBroadcast();
    }

    function _loadContracts() internal {
        console.log("Loading contracts from environment variables...");

        // Load core contracts
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER"));
        hook = IHooks(vm.envAddress("HOOK_ADDRESS"));

        console.log("PoolManager loaded:", address(poolManager));
        console.log("PositionManager loaded:", address(positionManager));
        console.log("YieldMaximizerHook loaded:", address(hook));

        // Load tokens
        weth = MockERC20(vm.envAddress("TOKEN_WETH"));
        usdc = MockERC20(vm.envAddress("TOKEN_USDC"));
        dai = MockERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = MockERC20(vm.envAddress("TOKEN_WBTC"));
        yieldToken = MockERC20(vm.envAddress("TOKEN_YIELD"));

        console.log("All contracts loaded successfully");
    }

    function _provideLiquidityToAllPools() internal {
        console.log("Providing liquidity to all pools...");

        // Pool configurations (must match existing pools)
        PoolConfig[] memory configs = _getPoolConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            _provideLiquidityToPool(configs[i]);
        }
    }

    function _getPoolConfigs() internal view returns (PoolConfig[] memory) {
        PoolConfig[] memory configs = new PoolConfig[](5);

        // 1. WETH/USDC
        CurrencyPair memory wethUsdc = _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(usdc)));
        configs[0] = PoolConfig({
            name: "WETH/USDC",
            currency0: wethUsdc.currency0,
            currency1: wethUsdc.currency1,
            fee: 3000,
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(2500, 1)
        });

        // 2. WETH/DAI
        CurrencyPair memory wethDai = _sortCurrencies(Currency.wrap(address(weth)), Currency.wrap(address(dai)));
        configs[1] = PoolConfig({
            name: "WETH/DAI",
            currency0: wethDai.currency0,
            currency1: wethDai.currency1,
            fee: 3000,
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(2500, 1)
        });

        // 3. WBTC/WETH
        CurrencyPair memory wbtcWeth = _sortCurrencies(Currency.wrap(address(wbtc)), Currency.wrap(address(weth)));
        configs[2] = PoolConfig({
            name: "WBTC/WETH",
            currency0: wbtcWeth.currency0,
            currency1: wbtcWeth.currency1,
            fee: 3000,
            tickSpacing: 60,
            sqrtPriceX96: _calculateSqrtPriceX96(20, 1)
        });

        // 4. USDC/DAI
        CurrencyPair memory usdcDai = _sortCurrencies(Currency.wrap(address(usdc)), Currency.wrap(address(dai)));
        configs[3] = PoolConfig({
            name: "USDC/DAI",
            currency0: usdcDai.currency0,
            currency1: usdcDai.currency1,
            fee: 500,
            tickSpacing: 10,
            sqrtPriceX96: _calculateSqrtPriceX96(1, 1)
        });

        // 5. YIELD/WETH
        CurrencyPair memory yieldWeth =
            _sortCurrencies(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth)));
        configs[4] = PoolConfig({
            name: "YIELD/WETH",
            currency0: yieldWeth.currency0,
            currency1: yieldWeth.currency1,
            fee: 10000,
            tickSpacing: 200,
            sqrtPriceX96: _calculateSqrtPriceX96(100, 1)
        });

        return configs;
    }

    function _provideLiquidityToPool(PoolConfig memory config) internal {
        console.log("\nProviding liquidity to pool:", config.name);

        // Create PoolKey with hook
        PoolKey memory poolKey = PoolKey({
            currency0: config.currency0,
            currency1: config.currency1,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: hook
        });

        // Calculate tick range
        (int24 tickLower, int24 tickUpper) = _calculateTickRange(config);
        console.log("  Tick range:", vm.toString(int256(tickLower)), "to", vm.toString(int256(tickUpper)));

        // Calculate token amounts
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(config);
        console.log("  Amount0:", amount0);
        console.log("  Amount1:", amount1);

        // Approve tokens for PositionManager
        _approveTokensForPositionManager(config.currency0, config.currency1, amount0, amount1);

        // Create position using PositionManager multicall
        _mintPosition(poolKey, tickLower, tickUpper, amount0, amount1);

        console.log("Liquidity provided successfully");
    }

    function _calculateTickRange(PoolConfig memory config) internal pure returns (int24 tickLower, int24 tickUpper) {
        // Use much wider tick ranges to ensure swaps work regardless of price
        int24 tickSpacing = config.tickSpacing;

        if (keccak256(abi.encodePacked(config.name)) == keccak256("WETH/USDC")) {
            tickLower = -1200; // Wider range for volatile pairs
            tickUpper = 1200;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("WETH/DAI")) {
            tickLower = -1200;
            tickUpper = 1200;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("WBTC/WETH")) {
            tickLower = -1200;
            tickUpper = 1200;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("USDC/DAI")) {
            // Much wider range for stablecoin pair to ensure swaps work
            tickLower = -1000; // Expanded from -100
            tickUpper = 1000; // Expanded from 100
        } else {
            // YIELD/WETH - keep wide range
            tickLower = -2000;
            tickUpper = 2000;
        }

        // Align to tick spacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        // Ensure valid range
        require(tickLower < tickUpper, "Invalid tick range");
        require(tickLower >= -887272 && tickUpper <= 887272, "Tick out of bounds");
    }

    function _calculateTokenAmounts(PoolConfig memory config)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        // Provide reasonable amounts for each pool
        if (keccak256(abi.encodePacked(config.name)) == keccak256("WETH/USDC")) {
            amount0 = Currency.unwrap(config.currency0) == address(usdc) ? 10000 * 10 ** 6 : 4 * 10 ** 18; // 10k USDC or 4 WETH
            amount1 = Currency.unwrap(config.currency1) == address(usdc) ? 10000 * 10 ** 6 : 4 * 10 ** 18;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("WETH/DAI")) {
            amount0 = Currency.unwrap(config.currency0) == address(dai) ? 10000 * 10 ** 18 : 4 * 10 ** 18; // 10k DAI or 4 WETH
            amount1 = Currency.unwrap(config.currency1) == address(dai) ? 10000 * 10 ** 18 : 4 * 10 ** 18;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("WBTC/WETH")) {
            amount0 = Currency.unwrap(config.currency0) == address(wbtc) ? 1 * 10 ** 8 : 20 * 10 ** 18; // 1 WBTC or 20 WETH
            amount1 = Currency.unwrap(config.currency1) == address(wbtc) ? 1 * 10 ** 8 : 20 * 10 ** 18;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("USDC/DAI")) {
            amount0 = Currency.unwrap(config.currency0) == address(usdc) ? 5000 * 10 ** 6 : 5000 * 10 ** 18; // 5k each
            amount1 = Currency.unwrap(config.currency1) == address(usdc) ? 5000 * 10 ** 6 : 5000 * 10 ** 18;
        } else if (keccak256(abi.encodePacked(config.name)) == keccak256("YIELD/WETH")) {
            amount0 = Currency.unwrap(config.currency0) == address(yieldToken) ? 50000 * 10 ** 18 : 5 * 10 ** 18; // 50k YIELD or 5 WETH
            amount1 = Currency.unwrap(config.currency1) == address(yieldToken) ? 50000 * 10 ** 18 : 5 * 10 ** 18;
        }
    }

    function _approveTokensForPositionManager(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1)
        internal
    {
        // Approve tokens for SimplePermit2 (since PositionManager uses Permit2 for transfers)
        address permit2Address = vm.envAddress("PERMIT2");
        IERC20(Currency.unwrap(currency0)).approve(permit2Address, amount0);
        IERC20(Currency.unwrap(currency1)).approve(permit2Address, amount1);

        console.log(" Tokens approved for SimplePermit2");
    }

    function _mintPosition(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal {
        // Use PositionManager.modifyLiquidities() with correct encoding
        // unlockData = abi.encode(bytes actions, bytes[] params)
        // where actions[i] corresponds to params[i]

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);

        // MINT_POSITION parameters
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            uint256(1e18), // liquidity amount
            amount0Max,
            amount1Max,
            msg.sender, // recipient
            bytes("") // hookData
        );

        // SETTLE_PAIR parameters
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        bytes memory unlockData = abi.encode(actions, params);

        // Execute via modifyLiquidities
        positionManager.modifyLiquidities(unlockData, block.timestamp + 60);

        console.log(" Position minted via PositionManager");
    }

    // Helper functions
    struct CurrencyPair {
        Currency currency0;
        Currency currency1;
    }

    function _sortCurrencies(Currency currencyA, Currency currencyB) internal pure returns (CurrencyPair memory) {
        if (Currency.unwrap(currencyA) < Currency.unwrap(currencyB)) {
            return CurrencyPair(currencyA, currencyB);
        } else {
            return CurrencyPair(currencyB, currencyA);
        }
    }

    function _calculateSqrtPriceX96(uint256 price0, uint256 price1) internal pure returns (uint160) {
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
}
