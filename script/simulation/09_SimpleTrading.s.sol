// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "../local/01_CreateTokens.s.sol";
import {YieldMaximizerHook} from "../../src/YieldMaximizerHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title Simple Trading Activity Generator
 * @notice Simplified version that uses deployer account to generate basic trading activity
 */
contract SimpleTrading is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts
    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    YieldMaximizerHook public yieldHook;

    // Token contracts
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Starting Simple Trading Activity Generation...");

        // Load contracts
        _loadContracts();

        // Execute simple trades to generate fees
        _executeSimpleTrades();

        console.log("Simple trading completed!");

        vm.stopBroadcast();
    }

    function _loadContracts() internal {
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        yieldHook = YieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));
        swapRouter = new PoolSwapTest(poolManager);

        weth = MockERC20(vm.envAddress("TOKEN_WETH"));
        usdc = MockERC20(vm.envAddress("TOKEN_USDC"));
        dai = MockERC20(vm.envAddress("TOKEN_DAI"));

        console.log("Contracts loaded successfully");
    }

    function _executeSimpleTrades() internal {
        console.log("Checking existing pool configurations...");

        // Test with the exact USDC/DAI configuration from the deployment
        PoolKey memory poolKey = _createPoolKey(
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dai)),
            500, // 0.05% fee - matches deployment
            10 // tick spacing - matches deployment
        );

        console.log("=== POOL DIAGNOSTICS ===");
        console.log("Pool Key - Token0:", Currency.unwrap(poolKey.currency0));
        console.log("Pool Key - Token1:", Currency.unwrap(poolKey.currency1));
        console.log("Pool Key - Fee:", poolKey.fee);
        console.log("Pool Key - TickSpacing:", uint256(int256(poolKey.tickSpacing)));

        // Check token balances
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        uint256 daiBalance = dai.balanceOf(msg.sender);
        console.log("USDC Balance:", usdcBalance);
        console.log("DAI Balance:", daiBalance);

        // Try much smaller trade first to stay within liquidity range
        uint256 usdcAmount = 10 * 10 ** 6; // 10 USDC (even smaller)

        if (usdcBalance < usdcAmount) {
            console.log("Insufficient USDC balance for trade");
            return;
        }

        usdc.approve(address(swapRouter), usdcAmount);
        console.log("Approved USDC for trading");

        // Determine swap direction properly
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(usdc);
        console.log("Swap direction (zeroForOne):", zeroForOne);

        console.log("Executing tiny USDC -> DAI trade (10 USDC)...");

        try swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(usdcAmount), // Exact input
                sqrtPriceLimitX96: 0 // No price limit
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bytes("")
        ) {
            console.log("SUCCESS: USDC -> DAI trade completed!");

            // Check balances after trade
            uint256 newUsdcBalance = usdc.balanceOf(msg.sender);
            uint256 newDaiBalance = dai.balanceOf(msg.sender);
            console.log("New USDC Balance:", newUsdcBalance);
            console.log("New DAI Balance:", newDaiBalance);
            console.log("USDC spent:", usdcBalance - newUsdcBalance);
            console.log("DAI received:", newDaiBalance - daiBalance);
        } catch Error(string memory reason) {
            console.log(string.concat("Trade failed with reason: ", reason));
        } catch (bytes memory lowLevelData) {
            console.log("=== ERROR ANALYSIS ===");
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                uint32 errorUint = uint32(errorSelector);
                console.log("Error selector (hex):", vm.toString(errorUint));

                // Decode known Uniswap V4 errors
                if (errorSelector == 0x7c693972) {
                    console.log("DECODED: PoolNotInitialized() - Pool needs to be initialized");
                } else if (errorSelector == 0x4faa8a69) {
                    console.log("DECODED: PoolAlreadyInitialized() - Pool already exists");
                } else if (errorSelector == 0x7c9c6e8f) {
                    console.log("DECODED: Likely insufficient liquidity or price out of range");
                } else {
                    console.log("UNKNOWN ERROR: Check Uniswap V4 documentation for error selector");
                }

                if (lowLevelData.length > 4) {
                    console.log("Additional error data present");
                }
            } else {
                console.log("No error data available");
            }
        }
    }

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
}
