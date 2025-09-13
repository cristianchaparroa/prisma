// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {YieldMaximizerHook} from "../../../src/YieldMaximizerHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/**
 * @title Simple Swap Test
 * @notice Performs a single swap to test if the YieldMaximizer hook is being called
 */
contract SimpleSwapTest is Script, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts
    IPoolManager public poolManager;
    YieldMaximizerHook public yieldHook;

    // Test tokens
    IERC20 public weth;
    IERC20 public usdc;
    
    // Callback storage
    PoolKey private _poolKey;
    SwapParams private _swapParams;
    uint256 private _swapAmount;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");

        // Load deployed contracts
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        yieldHook = YieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));

        // Load tokens
        weth = IERC20(vm.envAddress("TOKEN_WETH"));
        usdc = IERC20(vm.envAddress("TOKEN_USDC"));

        console2.log("=== SIMPLE SWAP TEST ===");
        console2.log("PoolManager:", address(poolManager));
        console2.log("Hook:", address(yieldHook));
        console2.log("WETH:", address(weth));
        console2.log("USDC:", address(usdc));

        vm.startBroadcast(deployerPrivateKey);

        // Create pool key for USDC/WETH (should match your existing pool)
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)), // USDC first (lower address)
            currency1: Currency.wrap(address(weth)), // WETH second
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(yieldHook))
        });

        PoolId poolId = poolKey.toId();
        console2.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Check deployer balances before swap
        uint256 usdcBefore = usdc.balanceOf(deployer);
        uint256 wethBefore = weth.balanceOf(deployer);

        console2.log("Balances BEFORE swap:");
        console2.log("  USDC:", usdcBefore);
        console2.log("  WETH:", wethBefore);

        // Universal Router swap setup
        uint256 swapAmount = 1 * 1e6; // 1 USDC
        address universalRouter = vm.envAddress("UNIVERSAL_ROUTER");

        console2.log("Using Universal Router:", universalRouter);
        console2.log("Swap amount:", swapAmount, "USDC");

        // Prepare swap parameters (USDC -> WETH)
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // USDC (token0) -> WETH (token1)
            amountSpecified: int256(swapAmount), // Exact input
            sqrtPriceLimitX96: 0 // No price limit
        });

        console2.log("=== EXECUTING SWAP ===");
        console2.log("Swapping", swapAmount, "USDC for WETH...");
        console2.log("zeroForOne:", swapParams.zeroForOne);
        console2.log("amountSpecified:", uint256(swapParams.amountSpecified));

        // Record events to track hook calls
        vm.recordLogs();

        // Store swap parameters for callback
        _poolKey = poolKey;
        _swapParams = swapParams;
        _swapAmount = swapAmount;
        
        console2.log("Using unlock/callback pattern for V4 swap");
        
        // Use proper V4 unlock/callback pattern
        try poolManager.unlock(abi.encode(deployer)) returns (bytes memory result) {
            console2.log("Unlock/callback swap completed!");
            BalanceDelta delta = abi.decode(result, (BalanceDelta));
            console2.logInt(delta.amount0());
            console2.logInt(delta.amount1());
        } catch Error(string memory reason) {
            console2.log("Unlock/callback swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Unlock/callback swap failed with low level error:");
            console2.logBytes(lowLevelData);
        }

        // Check if hook was called by looking for DebugSwapEntered event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool hookCalled = false;

        console2.log("=== EVENT ANALYSIS ===");
        console2.log("Total events emitted:", logs.length);

        for (uint i = 0; i < logs.length; i++) {
            // Check for standard HookSwap event signature: keccak256("HookSwap(bytes32,address,int128,int128,uint128,uint128)")
            if (logs[i].topics[0] == keccak256("HookSwap(bytes32,address,int128,int128,uint128,uint128)")) {
                hookCalled = true;
                console2.log("HOOK WAS CALLED! HookSwap event found");
                console2.log("  Event index:", i);
                console2.log("  Emitter:", logs[i].emitter);
                
                // Decode the event data
                bytes32 eventPoolId = logs[i].topics[1];
                address eventSender = address(uint160(uint256(logs[i].topics[2])));
                (int128 amount0, int128 amount1, uint128 hookFee0, uint128 hookFee1) = 
                    abi.decode(logs[i].data, (int128, int128, uint128, uint128));
                
                console2.log("  PoolId from event:", vm.toString(eventPoolId));
                console2.log("  Sender from event:", eventSender);
                console2.log("  Amount0:", vm.toString(amount0));
                console2.log("  Amount1:", vm.toString(amount1));
                break;
            }
        }

        if (!hookCalled) {
            console2.log("HOOK WAS NOT CALLED - No HookSwap event found");
            console2.log("This means the swap failed before reaching the hook");
            console2.log("Possible causes:");
            console2.log("  1. Pool doesn't exist with these parameters");
            console2.log("  2. No liquidity in the pool");
            console2.log("  3. Hook permissions issue");
            console2.log("  4. Token approval/balance issue");
        }

        // Check balances after swap
        uint256 usdcAfter = usdc.balanceOf(deployer);
        uint256 wethAfter = weth.balanceOf(deployer);

        console2.log("Balances AFTER swap:");
        console2.log("  USDC:", usdcAfter);
        console2.log("  WETH:", wethAfter);
        console2.log("  USDC change:", int256(usdcAfter) - int256(usdcBefore));
        console2.log("  WETH change:", int256(wethAfter) - int256(wethBefore));

        vm.stopBroadcast();

        console2.log("=== TEST COMPLETE ===");
        console2.log("Check Anvil logs for hook console.log messages:");
        console2.log("  Look for: '=== HOOK CALLED: _afterSwap ==='");
        console2.log("  If you see this message, the hook is working!");
        console2.log("  If not, there's a routing/permission issue.");
    }
    
    // IUnlockCallback implementation - Proper V4 settlement
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");
        
        address sender = abi.decode(data, (address));
        console2.log("unlockCallback called by:", sender);
        
        // First approve tokens to PoolManager if needed
        Currency currency0 = _poolKey.currency0;
        Currency currency1 = _poolKey.currency1;
        
        // Ensure tokens are approved for the PoolManager
        IERC20(Currency.unwrap(currency0)).approve(address(poolManager), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(poolManager), type(uint256).max);
        
        // Perform the swap inside the callback
        BalanceDelta delta = poolManager.swap(_poolKey, _swapParams, "");
        console2.log("SWAP EXECUTED IN CALLBACK!");
        console2.log("Delta amount0:", delta.amount0());
        console2.log("Delta amount1:", delta.amount1());
        
        // THIS MEANS THE HOOK WAS CALLED!
        // If we reach this point, the swap executed and the hook was triggered
        
        // Handle proper V4 settlement using the PoolManager interface
        if (delta.amount0() < 0) {
            // Pool owes us currency0, we take it
            poolManager.take(currency0, sender, uint256(-int256(delta.amount0())));
            console2.log("Took currency0:", uint256(-int256(delta.amount0())));
        }
        if (delta.amount0() > 0) {
            // We owe the pool currency0, we settle it
            // Transfer tokens to PoolManager first, then settle
            IERC20(Currency.unwrap(currency0)).transferFrom(sender, address(poolManager), uint256(int256(delta.amount0())));
            poolManager.settle();
            console2.log("Settled currency0:", uint256(int256(delta.amount0())));
        }
        
        if (delta.amount1() < 0) {
            // Pool owes us currency1, we take it
            poolManager.take(currency1, sender, uint256(-int256(delta.amount1())));
            console2.log("Took currency1:", uint256(-int256(delta.amount1())));
        }
        if (delta.amount1() > 0) {
            // We owe the pool currency1, we settle it
            // Transfer tokens to PoolManager first, then settle
            IERC20(Currency.unwrap(currency1)).transferFrom(sender, address(poolManager), uint256(int256(delta.amount1())));
            poolManager.settle();
            console2.log("Settled currency1:", uint256(int256(delta.amount1())));
        }
        
        console2.log("Token settlement completed successfully!");
        
        return abi.encode(delta);
    }
}
