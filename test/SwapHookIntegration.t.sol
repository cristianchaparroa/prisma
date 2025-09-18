//// SPDX-License-Identifier: MIT
//pragma solidity 0.8.26;
//
//import {Test} from "forge-std/Test.sol";
//import {console} from "forge-std/console.sol";
//import {YieldMaximizerHook} from "../src/YieldMaximizerHook.sol";
//import {SimpleDeployers} from "./utils/SimpleDeployers.sol";
//import {TestConstants} from "./utils/TestConstants.sol";
//import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
//import {PoolKey} from "v4-core/types/PoolKey.sol";
//import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
//import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
//import {IHooks} from "v4-core/interfaces/IHooks.sol";
//import {Hooks} from "v4-core/libraries/Hooks.sol";
//import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
//import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
//import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
//
///**
// * @title Comprehensive Swap Hook Integration Tests
// * @notice Tests that verify the hook integrates properly with Uniswap V4 swaps and fee distribution
// */
//contract SwapHookIntegrationTest is Test, SimpleDeployers {
//    using PoolIdLibrary for PoolKey;
//    using CurrencyLibrary for Currency;
//
//    YieldMaximizerHook hook;
//    PoolKey poolKey;
//    PoolId poolId;
//    Currency currency0;
//    Currency currency1;
//
//    address alice = address(0x1);
//    address bob = address(0x2);
//    address charlie = address(0x3);
//
//    uint24 constant FEE = 3000; // 0.3%
//    int24 constant TICK_SPACING = 60;
//
//    function setUp() public {
//        // Deploy V4 infrastructure properly
//        deployArtifacts();
//        (currency0, currency1) = deployCurrencyPair();
//
//        // Deploy hook
//        uint160 flags = uint160(
//            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
//                | Hooks.AFTER_SWAP_FLAG
//        );
//
//        bytes memory constructorArgs = abi.encode(poolManager);
//        address hookAddress =
//            deployHookToProperAddress("YieldMaximizerHook.sol:YieldMaximizerHook", constructorArgs, flags);
//        hook = YieldMaximizerHook(hookAddress);
//
//        // Create pool
//        (poolKey, poolId) =
//            createPool(currency0, currency1, IHooks(address(hook)), FEE, TICK_SPACING, TestConstants.SQRT_PRICE_1_1);
//
//        // Setup test users
//        _setupTestUsers();
//    }
//
//    function _setupTestUsers() internal {
//        console.log("Test users setup complete");
//    }
//
//    function test_swapTriggersAfterSwapHook() public {
//        // Alice activates strategy FIRST
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Alice adds liquidity to become active user
//        _addLiquidityForUser(alice, 1000000000000000000); // 1 ether worth
//
//        // Verify Alice is tracked as active user
//        address[] memory activeUsers = hook.getActiveUsers(poolId);
//        assertEq(activeUsers.length, 1, "Should have 1 active user");
//        assertEq(activeUsers[0], alice, "Alice should be the active user");
//
//        // Record Alice's fees before swap
//        YieldMaximizerHook.FeeAccounting memory feesBefore = hook.getUserFees(alice, poolId);
//
//        // Alice performs a swap to earn fees (fees go to swappers)
//        _performSwap(alice, true, 100000000000000000); // 0.1 ether
//
//        // Verify that _afterSwap was triggered and fees were distributed
//        YieldMaximizerHook.FeeAccounting memory feesAfter = hook.getUserFees(alice, poolId);
//
//        assertGt(
//            feesAfter.totalFeesEarned,
//            feesBefore.totalFeesEarned,
//            "_afterSwap hook should have been triggered and fees distributed"
//        );
//
//        assertGt(
//            feesAfter.pendingCompound, feesBefore.pendingCompound, "Pending compound amount should increase after swap"
//        );
//
//        console.log("_afterSwap hook was successfully triggered");
//        console.log("Fee increase:", feesAfter.totalFeesEarned - feesBefore.totalFeesEarned);
//    }
//
//    function test_swapGeneratesFeesAndDistributesToActiveUsers() public {
//        // Both Alice and Bob activate strategies FIRST
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        vm.prank(bob);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Both add liquidity to become active users
//        _addLiquidityForUser(alice, 2000000000000000000); // 2 ether
//        _addLiquidityForUser(bob, 1000000000000000000);   // 1 ether
//
//        // Verify both users are tracked as active
//        address[] memory activeUsers = hook.getActiveUsers(poolId);
//        assertEq(activeUsers.length, 2, "Should have 2 users with activated strategies");
//
//        // Record fees before swaps
//        YieldMaximizerHook.FeeAccounting memory aliceFeesBefore = hook.getUserFees(alice, poolId);
//        YieldMaximizerHook.FeeAccounting memory bobFeesBefore = hook.getUserFees(bob, poolId);
//
//        // Both users perform equal swaps (fees go to swappers)
//        uint256 swapAmount = 250000000000000000; // 0.25 ether
//        _performSwap(alice, true, swapAmount);
//        _performSwap(bob, true, swapAmount);
//
//        // Check fees after swaps
//        YieldMaximizerHook.FeeAccounting memory aliceFeesAfter = hook.getUserFees(alice, poolId);
//        YieldMaximizerHook.FeeAccounting memory bobFeesAfter = hook.getUserFees(bob, poolId);
//
//        // Calculate fee increases
//        uint256 aliceFeeIncrease = aliceFeesAfter.totalFeesEarned - aliceFeesBefore.totalFeesEarned;
//        uint256 bobFeeIncrease = bobFeesAfter.totalFeesEarned - bobFeesBefore.totalFeesEarned;
//
//        // Both users should have earned fees from their swaps
//        assertGt(aliceFeeIncrease, 0, "Alice should have earned fees");
//        assertGt(bobFeeIncrease, 0, "Bob should have earned fees");
//
//        // Since both swapped equal amounts, fees should be similar
//        uint256 ratio = (aliceFeeIncrease * 100) / bobFeeIncrease;
//        assertGe(ratio, 80, "Fees should be similar (Alice >= 80% of expected)");
//        assertLe(ratio, 120, "Fees should be similar (Alice <= 120% of expected)");
//
//        console.log("Fees correctly distributed to swappers");
//        console.log("Alice fee increase:", aliceFeeIncrease);
//        console.log("Bob fee increase:", bobFeeIncrease);
//    }
//
//    function test_swapWithActiveUsersDistributesProportionalFees() public {
//        // All three users activate strategies FIRST
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        vm.prank(bob);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        vm.prank(charlie);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // All add different amounts of liquidity
//        _addLiquidityForUser(alice, 3000000000000000000);  // 3 ether
//        _addLiquidityForUser(bob, 1000000000000000000);    // 1 ether
//        _addLiquidityForUser(charlie, 2000000000000000000); // 2 ether
//
//        // Verify all users are tracked as active
//        address[] memory activeUsers = hook.getActiveUsers(poolId);
//        assertEq(activeUsers.length, 3, "Should have 3 users with activated strategies");
//
//        // Record fees before swaps
//        YieldMaximizerHook.FeeAccounting memory aliceFeesBefore = hook.getUserFees(alice, poolId);
//        YieldMaximizerHook.FeeAccounting memory bobFeesBefore = hook.getUserFees(bob, poolId);
//        YieldMaximizerHook.FeeAccounting memory charlieFeesBefore = hook.getUserFees(charlie, poolId);
//
//        // Users perform swaps with different amounts (fees go to swappers based on swap amounts)
//        uint256 aliceSwapAmount = 600000000000000000;   // 0.6 ether (6x)
//        uint256 bobSwapAmount = 100000000000000000;     // 0.1 ether (1x)
//        uint256 charlieSwapAmount = 400000000000000000; // 0.4 ether (4x)
//
//        _performSwap(alice, true, aliceSwapAmount);
//        _performSwap(bob, true, bobSwapAmount);
//        _performSwap(charlie, true, charlieSwapAmount);
//
//        // Check fees after swaps
//        YieldMaximizerHook.FeeAccounting memory aliceFeesAfter = hook.getUserFees(alice, poolId);
//        YieldMaximizerHook.FeeAccounting memory bobFeesAfter = hook.getUserFees(bob, poolId);
//        YieldMaximizerHook.FeeAccounting memory charlieFeesAfter = hook.getUserFees(charlie, poolId);
//
//        // Calculate fee increases
//        uint256 aliceFeeIncrease = aliceFeesAfter.totalFeesEarned - aliceFeesBefore.totalFeesEarned;
//        uint256 bobFeeIncrease = bobFeesAfter.totalFeesEarned - bobFeesBefore.totalFeesEarned;
//        uint256 charlieFeeIncrease = charlieFeesAfter.totalFeesEarned - charlieFeesBefore.totalFeesEarned;
//
//        // All users should earn fees
//        assertGt(aliceFeeIncrease, 0, "Alice should earn fees");
//        assertGt(bobFeeIncrease, 0, "Bob should earn fees");
//        assertGt(charlieFeeIncrease, 0, "Charlie should earn fees");
//
//        // Verify proportional distribution based on swap amounts
//        // Expected ratios: Alice(0.6):Bob(0.1):Charlie(0.4) = 6:1:4
//
//        // Alice should earn ~6x Bob's fees
//        uint256 aliceToBobRatio = (aliceFeeIncrease * 100) / bobFeeIncrease;
//        assertGe(aliceToBobRatio, 500, "Alice should earn at least 5x Bob's fees");
//        assertLe(aliceToBobRatio, 700, "Alice should earn at most 7x Bob's fees");
//
//        // Charlie should earn ~4x Bob's fees
//        uint256 charlieToBobRatio = (charlieFeeIncrease * 100) / bobFeeIncrease;
//        assertGe(charlieToBobRatio, 350, "Charlie should earn at least 3.5x Bob's fees");
//        assertLe(charlieToBobRatio, 450, "Charlie should earn at most 4.5x Bob's fees");
//
//        console.log("Proportional fee distribution test passed");
//        console.log("Alice fees:", aliceFeeIncrease);
//        console.log("Bob fees:", bobFeeIncrease);
//        console.log("Charlie fees:", charlieFeeIncrease);
//    }
//
//    function test_swapSchedulesCompoundWhenThresholdMet() public {
//        // Alice activates strategy FIRST
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 100 gwei, 5);
//
//        // Alice adds liquidity to become active
//        _addLiquidityForUser(alice, 1000000000000000000); // 1 ether
//
//        // Check initial state
//        uint256 initialPendingBatchSize = hook.getPendingBatchSize(poolId);
//        assertEq(initialPendingBatchSize, 0, "Initially no pending compounds");
//
//        // With MIN_COMPOUND_AMOUNT = 1 wei, any swap should meet the threshold
//        // But first need to advance time past minimum interval
//        vm.warp(block.timestamp + hook.MIN_ACTION_INTERVAL() + 1);
//
//        // Alice performs a swap that should generate fees above threshold
//        _performSwap(alice, true, 100000000000000000); // 0.1 ether - should generate enough fees
//
//        // Check if compound was scheduled (if conditions are met)
//        YieldMaximizerHook.FeeAccounting memory feesAfter = hook.getUserFees(alice, poolId);
//
//        assertGt(feesAfter.totalFeesEarned, 0, "Alice should have earned fees");
//        assertGe(feesAfter.pendingCompound, hook.MIN_COMPOUND_AMOUNT(),
//            "Should meet minimum compound threshold");
//
//        console.log("Fee generation and threshold test completed");
//        console.log("Alice fees earned:", feesAfter.totalFeesEarned);
//        console.log("Pending compound:", feesAfter.pendingCompound);
//    }
//
//    function test_calculateFeesFromSwapAccuracy() public {
//        // Alice activates strategy FIRST
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 100 gwei, 5);
//
//        // Alice adds liquidity
//        _addLiquidityForUser(alice, 1000000000000000000); // 1 ether
//
//        // Test different swap amounts
//        uint256[] memory swapAmounts = new uint256[](3);
//        swapAmounts[0] = 10000000000000000;  // 0.01 ether
//        swapAmounts[1] = 100000000000000000; // 0.1 ether
//        swapAmounts[2] = 1000000000000000000; // 1 ether
//
//        console.log("=== Fee Calculation Accuracy Test ===");
//
//        for (uint256 i = 0; i < swapAmounts.length; i++) {
//            uint256 swapAmount = swapAmounts[i];
//
//            // Get Alice's fees before swap
//            YieldMaximizerHook.FeeAccounting memory feesBefore = hook.getUserFees(alice, poolId);
//
//            // Alice performs the swap
//            _performSwap(alice, true, swapAmount);
//
//            // Get Alice's fees after swap
//            YieldMaximizerHook.FeeAccounting memory feesAfter = hook.getUserFees(alice, poolId);
//
//            // Calculate the fee increase
//            uint256 actualFeeIncrease = feesAfter.totalFeesEarned - feesBefore.totalFeesEarned;
//
//            // Expected fees = swapAmount * feeTier / 1,000,000
//            uint256 expectedFees = (swapAmount * FEE) / 1000000;
//
//            console.log("Swap amount:", swapAmount);
//            console.log("Expected fees:", expectedFees);
//            console.log("Actual fees:", actualFeeIncrease);
//
//            // Verify basic sanity - should always earn some fees
//            assertGt(actualFeeIncrease, 0, "Should always earn some fees from swaps");
//
//            // Calculate accuracy if we have a reasonable expected amount
//            if (expectedFees > 0) {
//                uint256 accuracy = (actualFeeIncrease * 10000) / expectedFees; // Basis points
//                console.log("Accuracy:", accuracy, "basis points");
//
//                // Allow wide tolerance due to AMM mechanics, price impact, etc.
//                assertGe(accuracy, 1000, "Fee calculation should be at least 10% accurate"); // Very lenient
//            }
//        }
//
//        console.log("Fee calculation accuracy test completed");
//    }
//
//    // Helper functions
//    function _addLiquidityForUser(address user, uint256 liquidityAmount) internal {
//        vm.startPrank(user);
//
//        // Mint tokens for the user
//        MockERC20(Currency.unwrap(currency0)).mint(user, 1000 ether);
//        MockERC20(Currency.unwrap(currency1)).mint(user, 1000 ether);
//
//        // Approve tokens
//        MockERC20(Currency.unwrap(currency0)).approve(address(poolManager), type(uint256).max);
//        MockERC20(Currency.unwrap(currency1)).approve(address(poolManager), type(uint256).max);
//
//        // Add liquidity
//        poolManager.modifyLiquidity(
//            poolKey,
//            ModifyLiquidityParams({
//                tickLower: -60,
//                tickUpper: 60,
//                liquidityDelta: int256(liquidityAmount),
//                salt: bytes32(0)
//            }),
//            abi.encode(user)
//        );
//
//        vm.stopPrank();
//    }
//
//    function _performSwap(address user, bool zeroForOne, uint256 amountSpecified) internal {
//        vm.startPrank(user);
//
//        poolManager.swap(
//            poolKey,
//            SwapParams({
//                zeroForOne: zeroForOne,
//                amountSpecified: -int256(amountSpecified), // Exact input
//                sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
//            }),
//            abi.encode(user)
//        );
//
//        vm.stopPrank();
//    }
//}
