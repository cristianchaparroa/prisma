// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "../local/01_CreateTokens.s.sol";
import {YieldMaximizerHook} from "../../src/YieldMaximizerHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title Generate Realistic Trading Activity
 * @notice Creates 50+ random trades across all pools to generate fees for auto-compounding
 *         Uses multiple trader accounts with varied trading patterns and sizes
 */
contract GenerateTrading is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts (loaded from existing deployment)
    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    YieldMaximizerHook public yieldHook;

    // Token contracts (from existing deployment)
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;


    // Trading accounts (from existing distribution)
    address[] public traders;
    uint256[] public traderPrivateKeys;

    // Pool configurations for trading
    struct PoolConfig {
        string name;
        PoolKey poolKey;
        PoolId poolId;
        uint24 fee;
        Currency token0;
        Currency token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint256 baseTradeSize0; // Base trade size for token0
        uint256 baseTradeSize1; // Base trade size for token1
    }

    PoolConfig[] public poolConfigs;

    // Trading configuration
    struct TradeConfig {
        address trader;
        PoolConfig pool;
        bool zeroForOne; // Swap direction
        uint256 amountIn; // Swap amount
        uint256 minAmountOut; // Slippage protection
        string tradeType; // For logging
    }

    // Trading statistics
    struct TradingStats {
        uint256 totalTrades;
        uint256 totalVolumeETH;
        uint256 totalFeesGenerated;
        uint256 tradesPerPool;
        mapping(PoolId => uint256) poolVolume;
        mapping(PoolId => uint256) poolTrades;
        mapping(address => uint256) traderActivity;
    }

    TradingStats public stats;

    // Constants for realistic trading
    uint256 public constant TOTAL_TRADES = 75; // Increased for more activity
    uint256 public constant MIN_TRADE_SIZE = 50; // $50 equivalent
    uint256 public constant MAX_TRADE_SIZE = 15000; // $15,000 equivalent
    uint256 public constant SLIPPAGE_TOLERANCE = 300; // 3% slippage tolerance

    function run() external {
        console.log("Starting Realistic Trading Activity Generation...");

        // Load existing infrastructure
        _loadContracts();
        _loadTraders();
        _loadPoolConfigurations();

        console.log(string.concat("Total pools for trading: ", vm.toString(poolConfigs.length)));
        console.log(string.concat("Total traders: ", vm.toString(traders.length)));
        console.log(string.concat("Planned trades: ", vm.toString(TOTAL_TRADES)));

        // Generate and execute trades
        _generateTradingActivity();

        console.log("\n TRADING ACTIVITY GENERATION COMPLETE!");
        console.log("Trading Statistics:");
        console.log(string.concat("  Total Trades Executed: ", vm.toString(stats.totalTrades)));
        console.log(string.concat("  Estimated Fees Generated: $", vm.toString(_estimateTotalFeesUSD())));
        console.log("Ready for auto-compound monitoring");

        // Save trading statistics
        _saveTradingStats();
    }

    function _loadContracts() internal {
        console.log("Loading contracts from existing deployment...");

        // Load core contracts
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        yieldHook = YieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));

        // Deploy swap router for testing (if not exists)
        swapRouter = new PoolSwapTest(poolManager);

        console.log(string.concat("  PoolManager: ", vm.toString(address(poolManager))));
        console.log(string.concat("  YieldMaximizerHook: ", vm.toString(address(yieldHook))));
        console.log(string.concat("  SwapRouter: ", vm.toString(address(swapRouter))));

        // Load token contracts
        weth = IERC20(vm.envAddress("TOKEN_WETH"));
        usdc = IERC20(vm.envAddress("TOKEN_USDC"));
        dai = IERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = IERC20(vm.envAddress("TOKEN_WBTC"));

        console.log("All contracts loaded successfully");
    }

    function _loadTraders() internal {
        console.log("Loading trader accounts...");

        // Load all test accounts as potential traders (skip deployer account 0)
        for (uint256 i = 1; i <= 9; i++) {
            try vm.envAddress(string.concat("ACCOUNT_", vm.toString(i), "_ADDRESS")) returns (address trader) {
                traders.push(trader);
                uint256 privateKey = vm.envUint(string.concat("ACCOUNT_", vm.toString(i), "_PRIVATE_KEY"));
                traderPrivateKeys.push(privateKey);
            } catch {
                console.log(
                    string.concat(
                        "  Trader ", vm.toString(i), " not found, stopping at ", vm.toString(i - 1), " traders"
                    )
                );
                break;
            }
        }

        console.log(string.concat("  Loaded ", vm.toString(traders.length), " trader accounts"));
    }

    function _loadPoolConfigurations() internal {
        console.log("Setting up pool configurations for trading...");

        // WETH/USDC Pool - Highest volume expected
        PoolKey memory wethUsdcKey =
            _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), 3000, 60);
        poolConfigs.push(
            PoolConfig({
                name: "WETH/USDC",
                poolKey: wethUsdcKey,
                poolId: wethUsdcKey.toId(),
                fee: 3000,
                token0: wethUsdcKey.currency0,
                token1: wethUsdcKey.currency1,
                token0Decimals: _getTokenDecimals(wethUsdcKey.currency0),
                token1Decimals: _getTokenDecimals(wethUsdcKey.currency1),
                baseTradeSize0: 1 * 10 ** 18, // 1 WETH base size
                baseTradeSize1: 2500 * 10 ** 6 // 2500 USDC base size
            })
        );

        // WETH/DAI Pool
        PoolKey memory wethDaiKey = _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(dai)), 3000, 60);
        poolConfigs.push(
            PoolConfig({
                name: "WETH/DAI",
                poolKey: wethDaiKey,
                poolId: wethDaiKey.toId(),
                fee: 3000,
                token0: wethDaiKey.currency0,
                token1: wethDaiKey.currency1,
                token0Decimals: _getTokenDecimals(wethDaiKey.currency0),
                token1Decimals: _getTokenDecimals(wethDaiKey.currency1),
                baseTradeSize0: 1 * 10 ** 18, // 1 WETH base size
                baseTradeSize1: 2500 * 10 ** 18 // 2500 DAI base size
            })
        );

        // USDC/DAI Pool - Stablecoin arbitrage
        PoolKey memory usdcDaiKey = _createPoolKey(Currency.wrap(address(usdc)), Currency.wrap(address(dai)), 500, 10);
        poolConfigs.push(
            PoolConfig({
                name: "USDC/DAI",
                poolKey: usdcDaiKey,
                poolId: usdcDaiKey.toId(),
                fee: 500,
                token0: usdcDaiKey.currency0,
                token1: usdcDaiKey.currency1,
                token0Decimals: _getTokenDecimals(usdcDaiKey.currency0),
                token1Decimals: _getTokenDecimals(usdcDaiKey.currency1),
                baseTradeSize0: 1000 * 10 ** 6, // 1000 USDC base size
                baseTradeSize1: 1000 * 10 ** 18 // 1000 DAI base size
            })
        );

        // WBTC/WETH Pool
        PoolKey memory wbtcWethKey =
            _createPoolKey(Currency.wrap(address(wbtc)), Currency.wrap(address(weth)), 3000, 60);
        poolConfigs.push(
            PoolConfig({
                name: "WBTC/WETH",
                poolKey: wbtcWethKey,
                poolId: wbtcWethKey.toId(),
                fee: 3000,
                token0: wbtcWethKey.currency0,
                token1: wbtcWethKey.currency1,
                token0Decimals: _getTokenDecimals(wbtcWethKey.currency0),
                token1Decimals: _getTokenDecimals(wbtcWethKey.currency1),
                baseTradeSize0: 0.1 * 10 ** 8, // 0.1 WBTC base size
                baseTradeSize1: 2 * 10 ** 18 // 2 WETH base size
            })
        );

        // YIELD/WETH Pool - New token with higher volatility
//        PoolKey memory yieldWethKey =
//            _createPoolKey(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth)), 10000, 200);
//        poolConfigs.push(
//            PoolConfig({
//                name: "YIELD/WETH",
//                poolKey: yieldWethKey,
//                poolId: yieldWethKey.toId(),
//                fee: 10000,
//                token0: yieldWethKey.currency0,
//                token1: yieldWethKey.currency1,
//                token0Decimals: _getTokenDecimals(yieldWethKey.currency0),
//                token1Decimals: _getTokenDecimals(yieldWethKey.currency1),
//                baseTradeSize0: 1000 * 10 ** 18, // 1000 YIELD base size
//                baseTradeSize1: 0.5 * 10 ** 18 // 0.5 WETH base size
//            })
//        );

        console.log(string.concat("Loaded ", vm.toString(poolConfigs.length), " pool configurations"));
    }

    function _generateTradingActivity() internal {
        console.log("\n Generating realistic trading patterns...");

        // Generate trades with realistic distribution
        TradeConfig[] memory trades = _generateTradeConfigurations();

        console.log(string.concat("Generated ", vm.toString(trades.length), " trade configurations"));

        // Execute all trades
        for (uint256 i = 0; i < trades.length; i++) {
            _executeTrade(trades[i]);

            // Add small delay between trades for realism
            if (i % 10 == 0) {
                console.log(string.concat("  Executed ", vm.toString(i + 1), " trades..."));
            }
        }
    }

    function _generateTradeConfigurations() internal view returns (TradeConfig[] memory) {
        TradeConfig[] memory trades = new TradeConfig[](TOTAL_TRADES);
        uint256 tradeIndex = 0;

        // Generate trades with realistic patterns
        for (uint256 i = 0; i < TOTAL_TRADES && tradeIndex < TOTAL_TRADES; i++) {
            // Use pseudo-random selection with deterministic seed
            uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, i, block.prevrandao)));

            // Select trader (weighted towards whale for larger trades)
            address trader = _selectTrader(seed);

            // Select pool (weighted towards major pairs)
            PoolConfig memory pool = _selectPool(seed);

            // Determine trade direction
            bool zeroForOne = (seed % 2) == 0;

            // Calculate trade size based on trader type and pool
            uint256 amountIn = _calculateTradeSize(trader, pool, seed);

            // Skip if trader doesn't have enough tokens
            if (!_hasEnoughTokens(trader, pool, zeroForOne, amountIn)) {
                continue;
            }

            // Calculate minimum amount out (with slippage tolerance)
            uint256 minAmountOut = _calculateMinAmountOut(pool, zeroForOne, amountIn);

            trades[tradeIndex] = TradeConfig({
                trader: trader,
                pool: pool,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                tradeType: _getTradeType(trader, amountIn)
            });

            tradeIndex++;
        }

        // Resize array to actual number of valid trades
        TradeConfig[] memory validTrades = new TradeConfig[](tradeIndex);
        for (uint256 i = 0; i < tradeIndex; i++) {
            validTrades[i] = trades[i];
        }

        return validTrades;
    }

    function _selectTrader(uint256 seed) internal view returns (address) {
        // Weight selection towards whale (account 9) for 20% of trades
        if (seed % 5 == 0 && traders.length >= 9) {
            return traders[8]; // Account 9 (whale) - index 8
        }

        // Regular selection for other trades
        return traders[seed % traders.length];
    }

    function _selectPool(uint256 seed) internal view returns (PoolConfig memory) {
        // Weight pool selection for realistic volume distribution
        uint256 poolSelector = seed % 100;

        if (poolSelector < 40) {
            return poolConfigs[0]; // WETH/USDC - 40% of trades
        } else if (poolSelector < 70) {
            return poolConfigs[1]; // WETH/DAI - 30% of trades
        } else if (poolSelector < 85) {
            return poolConfigs[2]; // USDC/DAI - 15% of trades
        } else {
            return poolConfigs[3]; // WBTC/WETH - 15% of trades
        }
    }

    function _calculateTradeSize(address trader, PoolConfig memory pool, uint256 seed)
        internal
        view
        returns (uint256)
    {
        bool isWhale = _isWhaleTrader(trader);
        uint256 sizeMultiplier = seed % 10 + 1; // 1-10x multiplier

        uint256 baseSize;
        bool useToken0 = (seed % 2) == 0;

        if (useToken0) {
            baseSize = pool.baseTradeSize0;
        } else {
            baseSize = pool.baseTradeSize1;
        }

        if (isWhale) {
            // Whale trades: 5-50x base size
            return baseSize * (5 + (sizeMultiplier % 10));
        } else {
            // Regular trades: Use smaller base amounts but avoid zero
            // Instead of dividing by 10, use a smaller base amount
            uint256 regularBaseSize = baseSize / 20; // Start with 5% of base
            if (regularBaseSize == 0) {
                // Ensure minimum trade size
                if (Currency.unwrap(pool.token0) == address(usdc) || Currency.unwrap(pool.token1) == address(usdc)) {
                    regularBaseSize = 100 * 10 ** 6; // 100 USDC minimum
                } else if (
                    Currency.unwrap(pool.token0) == address(wbtc) || Currency.unwrap(pool.token1) == address(wbtc)
                ) {
                    regularBaseSize = 1 * 10 ** 6; // 0.01 WBTC minimum
                } else {
                    regularBaseSize = 1 * 10 ** 17; // 0.1 ETH/token minimum
                }
            }
            return regularBaseSize * sizeMultiplier;
        }
    }

    function _hasEnoughTokens(address trader, PoolConfig memory pool, bool zeroForOne, uint256 amountIn)
        internal
        view
        returns (bool)
    {
        Currency tokenIn = zeroForOne ? pool.token0 : pool.token1;
        uint256 balance = IERC20(Currency.unwrap(tokenIn)).balanceOf(trader);
        return balance >= amountIn;
    }

    function _calculateMinAmountOut(PoolConfig memory pool, bool zeroForOne, uint256 amountIn)
        internal
        pure
        returns (uint256)
    {
        // Simple approximation for minimum amount out (accounting for slippage)
        // In real implementation, you'd want to call quoter or use more sophisticated calculation
        uint256 estimatedOut;

        if (zeroForOne) {
            // Estimate based on approximate price ratios
            if (keccak256(abi.encodePacked(pool.name)) == keccak256("WETH/USDC")) {
                estimatedOut = amountIn * 2500 / 10 ** 12; // ~2500 USDC per WETH
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("WETH/DAI")) {
                estimatedOut = amountIn * 2500; // ~2500 DAI per WETH
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("USDC/DAI")) {
                estimatedOut = amountIn * 10 ** 12; // ~1:1 USDC:DAI
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("WBTC/WETH")) {
                estimatedOut = amountIn * 20 * 10 ** 10; // ~20 WETH per WBTC
            } else {
                // Default calculation for unknown pools
                estimatedOut = amountIn;
            }
        } else {
            // Reverse calculations
            if (keccak256(abi.encodePacked(pool.name)) == keccak256("WETH/USDC")) {
                estimatedOut = amountIn * 10 ** 12 / 2500; // USDC to WETH
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("WETH/DAI")) {
                estimatedOut = amountIn / 2500; // DAI to WETH
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("USDC/DAI")) {
                estimatedOut = amountIn / 10 ** 12; // DAI to USDC
            } else if (keccak256(abi.encodePacked(pool.name)) == keccak256("WBTC/WETH")) {
                estimatedOut = amountIn / (20 * 10 ** 10); // WETH to WBTC
            } else {
                // Default calculation for unknown pools
                estimatedOut = amountIn;
            }
        }

        // Apply slippage tolerance (3%)
        return estimatedOut * (10000 - SLIPPAGE_TOLERANCE) / 10000;
    }

    function _executeTrade(TradeConfig memory trade) internal {
        console.log(string.concat("Executing ", trade.tradeType, " trade in ", trade.pool.name));
        console.log(string.concat("  Trader: ", vm.toString(trade.trader)));
        console.log(string.concat("  Direction: ", trade.zeroForOne ? "Token0 -> Token1" : "Token1 -> Token0"));
        console.log(
            string.concat(
                "  Amount In: ",
                _formatAmount(trade.amountIn, trade.zeroForOne ? trade.pool.token0Decimals : trade.pool.token1Decimals)
            )
        );

        // Get trader's private key
        uint256 traderIndex = _getTraderIndex(trade.trader);
        uint256 traderPrivateKey = traderPrivateKeys[traderIndex];

        vm.startBroadcast(traderPrivateKey);

        // Approve tokens for swapping
        Currency tokenIn = trade.zeroForOne ? trade.pool.token0 : trade.pool.token1;
        IERC20(Currency.unwrap(tokenIn)).approve(address(swapRouter), trade.amountIn);

        // Execute swap
        try swapRouter.swap(
            trade.pool.poolKey,
            SwapParams({
                zeroForOne: trade.zeroForOne,
                amountSpecified: -int256(trade.amountIn), // Exact input
                sqrtPriceLimitX96: trade.zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342 // No price limit
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bytes("")
        ) returns (BalanceDelta delta) {
            console.log(" Trade executed successfully");

            // Update statistics
            stats.totalTrades++;
            stats.poolTrades[trade.pool.poolId]++;
            stats.traderActivity[trade.trader]++;

            // Estimate fees generated (pool fee * trade size)
            uint256 feeAmount = trade.amountIn * trade.pool.fee / 1000000;
            stats.totalFeesGenerated += feeAmount;
            stats.poolVolume[trade.pool.poolId] += trade.amountIn;
        } catch Error(string memory reason) {
            console.log(" Trade failed:", reason);
        } catch {
            console.log(" Trade failed: Unknown error");
        }

        vm.stopBroadcast();
    }

    function _saveTradingStats() internal {
        console.log("\n Saving trading statistics...");

        string memory tradingInfo = "# Trading Activity Results\n";
        tradingInfo = string.concat(tradingInfo, "TOTAL_TRADES_EXECUTED=", vm.toString(stats.totalTrades), "\n");
        tradingInfo = string.concat(tradingInfo, "TOTAL_FEES_GENERATED=", vm.toString(stats.totalFeesGenerated), "\n");
        tradingInfo = string.concat(tradingInfo, "UNIQUE_TRADERS=", vm.toString(traders.length), "\n");
        tradingInfo = string.concat(tradingInfo, "POOLS_WITH_ACTIVITY=", vm.toString(poolConfigs.length), "\n");
        tradingInfo = string.concat(tradingInfo, "TRADING_TIMESTAMP=", vm.toString(block.timestamp), "\n");

        // Add pool-specific stats
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            PoolConfig memory pool = poolConfigs[i];
            tradingInfo = string.concat(tradingInfo, "POOL_", vm.toString(i), "_NAME=", pool.name, "\n");
            tradingInfo = string.concat(
                tradingInfo, "POOL_", vm.toString(i), "_TRADES=", vm.toString(stats.poolTrades[pool.poolId]), "\n"
            );
            tradingInfo = string.concat(
                tradingInfo, "POOL_", vm.toString(i), "_VOLUME=", vm.toString(stats.poolVolume[pool.poolId]), "\n"
            );
        }

        vm.writeFile("./deployments/simulation-trading.env", tradingInfo);
        console.log(" Trading stats saved to: ./deployments/simulation-trading.env");
    }

    // Helper functions
    function _createPoolKey(Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing)
        internal
        view
        returns (PoolKey memory)
    {
        // Sort currencies
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

        return
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: yieldHook});
    }

    function _getTokenDecimals(Currency currency) internal view returns (uint8) {
        address token = Currency.unwrap(currency);
        if (token == address(usdc) || token == address(wbtc)) {
            return token == address(usdc) ? 6 : 8;
        }
        return 18; // Default for WETH, DAI, YIELD
    }

    function _isWhaleTrader(address trader) internal view returns (bool) {
        // Last trader is typically the whale (account 9)
        return traders.length > 0 && trader == traders[traders.length - 1];
    }

    function _getTraderIndex(address trader) internal view returns (uint256) {
        for (uint256 i = 0; i < traders.length; i++) {
            if (traders[i] == trader) {
                return i;
            }
        }
        revert("Trader not found");
    }

    function _getTradeType(address trader, uint256 amountIn) internal view returns (string memory) {
        if (_isWhaleTrader(trader)) {
            return "Whale";
        } else if (amountIn > 5 ether) {
            // Rough threshold for large trades
            return "Large";
        } else if (amountIn > 0.5 ether) {
            return "Medium";
        } else {
            return "Small";
        }
    }

    function _formatAmount(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        if (decimals == 6) {
            return string.concat(vm.toString(amount / 10 ** 6), " (6 dec)");
        } else if (decimals == 8) {
            return string.concat(vm.toString(amount / 10 ** 8), " (8 dec)");
        } else {
            return string.concat(vm.toString(amount / 10 ** 18), " (18 dec)");
        }
    }

    function _estimateTotalFeesUSD() internal view returns (uint256) {
        // Rough estimate of total fees in USD equivalent
        // This is a simplified calculation for display purposes
        return stats.totalFeesGenerated / 10 ** 15; // Convert to rough USD estimate
    }
}
