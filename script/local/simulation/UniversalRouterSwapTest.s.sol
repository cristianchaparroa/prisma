// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title UniversalRouterSwapTest
 * @notice Test script to execute V4 swaps using proper unlock callback pattern
 * @dev This will trigger hooks and emit real PoolManager Swap events
 */
contract UniversalRouterSwapTest is Script, IUnlockCallback {
    using PoolIdLibrary for PoolKey;

    IPoolManager public poolManager;
    PoolKey public poolKey;
    SwapParams public swapParams;
    address public swapSender;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address deployer = vm.envAddress("ANVIL_ADDRESS");
        
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address tokenUSDC = vm.envAddress("TOKEN_USDC");
        address tokenWETH = vm.envAddress("TOKEN_WETH");

        console2.log("=== UNIVERSAL ROUTER SWAP TEST ===");
        console2.log("PoolManager:", address(poolManager));
        console2.log("Hook:", hookAddress);
        console2.log("USDC:", tokenUSDC);
        console2.log("WETH:", tokenWETH);
        console2.log("Deployer:", deployer);

        // Create the pool key for USDC/WETH
        poolKey = PoolKey({
            currency0: Currency.wrap(tokenUSDC),
            currency1: Currency.wrap(tokenWETH), 
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        PoolId poolId = poolKey.toId();
        console2.log("Pool ID:");
        console2.logBytes32(PoolId.unwrap(poolId));

        vm.startBroadcast(deployerPrivateKey);

        // Check balances
        uint256 usdcBalance = IERC20(tokenUSDC).balanceOf(deployer);
        uint256 wethBalance = IERC20(tokenWETH).balanceOf(deployer);

        console2.log("Balances BEFORE swap:");
        console2.log("  USDC:", usdcBalance);
        console2.log("  WETH:", wethBalance);

        uint256 swapAmount = 1000000; // 1 USDC (6 decimals)
        require(usdcBalance >= swapAmount, "Insufficient USDC balance");

        // Approve USDC to this contract (so we can transfer in unlockCallback)
        IERC20(tokenUSDC).approve(address(this), swapAmount);

        // Setup swap parameters
        swapParams = SwapParams({
            zeroForOne: true, // USDC -> WETH
            amountSpecified: -int256(swapAmount), // Exact input (negative)
            sqrtPriceLimitX96: 4295128740 // Very low price limit
        });

        swapSender = deployer;

        console2.log("Executing V4 swap using unlock callback pattern...");
        console2.log("Amount:", swapAmount, "USDC");
        console2.log("Direction: USDC -> WETH");

        try this.executeSwap() returns (BalanceDelta delta) {
            console2.log("SUCCESS: Swap executed!");
            console2.log("Delta amount0:", int256(delta.amount0()));
            console2.log("Delta amount1:", int256(delta.amount1()));

            // Check balances after
            uint256 usdcBalanceAfter = IERC20(tokenUSDC).balanceOf(deployer);
            uint256 wethBalanceAfter = IERC20(tokenWETH).balanceOf(deployer);

            console2.log("Balances AFTER swap:");
            console2.log("  USDC:", usdcBalanceAfter);
            console2.log("  WETH:", wethBalanceAfter);

            console2.log("Changes:");
            console2.log("  USDC change:", int256(usdcBalanceAfter) - int256(usdcBalance));
            console2.log("  WETH change:", int256(wethBalanceAfter) - int256(wethBalance));

        } catch Error(string memory reason) {
            console2.log("FAILED: Swap failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("FAILED: Swap failed with low-level error");
            console2.log("Error data length:", lowLevelData.length);
        }

        vm.stopBroadcast();

        console2.log("=== TEST COMPLETE ===");
        console2.log("If swap succeeded, check your EventCollector for:");
        console2.log("1. Standard Swap event from PoolManager");
        console2.log("2. Hook events from YieldMaximizerHook (if enabled)");
    }

    function executeSwap() external returns (BalanceDelta) {
        // Use the unlock pattern to execute the swap
        bytes memory result = poolManager.unlock(abi.encode(swapSender));
        return abi.decode(result, (BalanceDelta));
    }

    /**
     * @notice Callback function called by PoolManager during unlock
     * @dev This is where the actual swap happens and settlement occurs
     */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        address sender = abi.decode(data, (address));

        console2.log("unlockCallback called");
        console2.log("Sender:", sender);

        // Execute the swap - this will trigger hooks and emit PoolManager events
        BalanceDelta delta = poolManager.swap(poolKey, swapParams, "");

        console2.log("Swap executed in callback!");
        console2.log("Delta amount0:", int256(delta.amount0()));
        console2.log("Delta amount1:", int256(delta.amount1()));

        // Handle settlement - this is CRITICAL for V4
        _settleSwap(delta, sender);

        return abi.encode(delta);
    }

    /**
     * @notice Handle token settlement after swap
     * @dev Properly transfer tokens to/from PoolManager
     */
    function _settleSwap(BalanceDelta delta, address sender) internal {
        Currency currency0 = poolKey.currency0; // USDC
        Currency currency1 = poolKey.currency1; // WETH

        // Handle currency0 (USDC) settlement
        if (delta.amount0() > 0) {
            // We owe the pool USDC - transfer from sender to PoolManager
            IERC20(Currency.unwrap(currency0)).transferFrom(
                sender,
                address(poolManager),
                uint256(int256(delta.amount0()))
            );
            // Settle the debt with PoolManager
            poolManager.settle();
            console2.log("Settled USDC:", uint256(int256(delta.amount0())));
        } else if (delta.amount0() < 0) {
            // Pool owes us USDC - take it from PoolManager
            poolManager.take(currency0, sender, uint256(-int256(delta.amount0())));
            console2.log("Took USDC:", uint256(-int256(delta.amount0())));
        }

        // Handle currency1 (WETH) settlement  
        if (delta.amount1() > 0) {
            // We owe the pool WETH - transfer from sender to PoolManager
            IERC20(Currency.unwrap(currency1)).transferFrom(
                sender,
                address(poolManager),
                uint256(int256(delta.amount1()))
            );
            // Settle the debt with PoolManager
            poolManager.settle();
            console2.log("Settled WETH:", uint256(int256(delta.amount1())));
        } else if (delta.amount1() < 0) {
            // Pool owes us WETH - take it from PoolManager
            poolManager.take(currency1, sender, uint256(-int256(delta.amount1())));
            console2.log("Took WETH:", uint256(-int256(delta.amount1())));
        }

        console2.log("Token settlement completed successfully!");
    }
}