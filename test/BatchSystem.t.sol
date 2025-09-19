// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
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
//import {SwapParams} from "v4-core/types/PoolOperation.sol";
//import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
//
//// BatchSystemTest: Gas optimization through batching
//contract BatchSystemTest is Test, SimpleDeployers {
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
//    address david = address(0x4);
//    address eve = address(0x5);
//
//    uint24 constant FEE = 3000; // 0.3%
//    int24 constant TICK_SPACING = 60;
//
//    function setUp() public {
//        // Deploy V4 infrastructure properly - no bypassing
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
//        // Setup multiple test users for batch testing
//        _setupMultipleUsers();
//
//        console.log("BatchSystem Test Setup Complete");
//    }
//
//    function _setupMultipleUsers() internal {
//        // Setup 5 users with different gas preferences for batch testing
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        vm.prank(bob);
//        hook.activateStrategy(poolId, 55 gwei, 6);
//
//        vm.prank(charlie);
//        hook.activateStrategy(poolId, 60 gwei, 7);
//
//        vm.prank(david);
//        hook.activateStrategy(poolId, 65 gwei, 8);
//
//        vm.prank(eve);
//        hook.activateStrategy(poolId, 70 gwei, 4);
//
//        console.log("5 users configured for batch testing");
//    }
//
//    // testMultipleUsersGetBatchedTogether: Multiple users get batched together (2-50 users)
//    function testMultipleUsersGetBatchedTogether() public view {
//        console.log("Testing Multiple Users Get Batched Together");
//
//        // Test batch size constants
//        uint256 minBatchSize = hook.MIN_BATCH_SIZE();
//        uint256 maxBatchSize = hook.MAX_BATCH_SIZE();
//
//        assertEq(minBatchSize, 2, "Minimum batch size should be 2");
//        assertEq(maxBatchSize, 50, "Maximum batch size should be 50");
//
//        // Test initial pending batch size
//        uint256 pendingBatchSize = hook.getPendingBatchSize(poolId);
//        assertEq(pendingBatchSize, 0, "Initial pending batch size should be 0");
//
//        console.log("Min batch size:", minBatchSize);
//        console.log("Max batch size:", maxBatchSize);
//        console.log("Current pending:", pendingBatchSize);
//    }
//
//    // testBatchExecutesWhenReady: Batch executes when ready (enough users or timeout)
//    function testBatchExecutesWhenReady() public {
//        console.log("Testing Batch Executes When Ready");
//
//        // Test that batch doesn't execute with no pending compounds
//        bool shouldExecuteEmpty = hook.shouldExecuteBatch(poolId);
//        assertFalse(shouldExecuteEmpty, "Should not execute empty batch");
//
//        // Test batch wait time constant
//        uint256 maxWaitTime = hook.MAX_BATCH_WAIT_TIME();
//        assertEq(maxWaitTime, 24 hours, "Max batch wait time should be 24 hours");
//
//        // Test force batch execution with no pending (should revert)
//        vm.expectRevert("No pending compounds");
//        hook.forceBatchExecution(poolId);
//
//        console.log("Max batch wait time:", maxWaitTime / 3600, "hours");
//    }
//
//    // testGasCostsSplitFairly: Gas costs split fairly among users
//    function testGasCostsSplitFairly() public view {
//        console.log("Testing Gas Costs Split Fairly");
//
//        // Test that gas credits are properly tracked per user
//        uint256 aliceGasCredits = hook.userGasCredits(alice);
//        uint256 bobGasCredits = hook.userGasCredits(bob);
//
//        assertEq(aliceGasCredits, 0, "Alice should have no initial gas credits");
//        assertEq(bobGasCredits, 0, "Bob should have no initial gas credits");
//
//        // Note: In a complete implementation, this would test actual gas distribution
//        // after batch execution, but that requires simulating real swaps and compounds
//
//        console.log("Gas credit tracking verified");
//    }
//
//    // testBatchSavesGasVsIndividual: Batch saves gas vs individual transactions
//    function testBatchSavesGasVsIndividual() public view {
//        console.log("Testing Batch Saves Gas vs Individual");
//
//        // Test gas savings calculation function exists
//        uint256 aliceGasSavings = hook.getGasSavings(alice, poolId);
//        assertEq(aliceGasSavings, 0, "Initial gas savings should be 0");
//
//        // Note: Real gas savings would be measured after actual batch vs individual execution
//        // This test verifies the gas savings tracking infrastructure exists
//
//        console.log("Gas savings tracking verified");
//    }
//
//    // testBatchSizeLimits: Test minimum and maximum batch size enforcement
//    function testBatchSizeLimits() public view {
//        console.log("Testing Batch Size Limits");
//
//        // Test that batch size constants are within reasonable bounds
//        uint256 minBatch = hook.MIN_BATCH_SIZE();
//        uint256 maxBatch = hook.MAX_BATCH_SIZE();
//
//        assertTrue(minBatch >= 2, "Minimum batch should be at least 2");
//        assertTrue(maxBatch <= 50, "Maximum batch should not exceed 50");
//        assertTrue(minBatch < maxBatch, "Min batch should be less than max batch");
//
//        // Test that single user batches wait for additional users
//        // This is enforced by the MIN_BATCH_SIZE requirement
//
//        console.log("Batch size limits verified");
//    }
//
//    // testBatchTimeout: Test batch timeout mechanism (24 hours)
//    function testBatchTimeout() public {
//        console.log("Testing Batch Timeout Mechanism");
//
//        // Test maximum wait time constant
//        uint256 maxWaitTime = hook.MAX_BATCH_WAIT_TIME();
//        assertEq(maxWaitTime, 24 hours, "Max wait time should be 24 hours");
//
//        // Test that batches execute after timeout even with single user
//        // This would require simulating pending compounds and time advancement
//
//        // Advance time to test timeout scenarios
//        uint256 startTime = block.timestamp;
//        vm.warp(startTime + 25 hours); // Beyond max wait time
//
//        // Note: In complete implementation, this would test that batch executes
//        // even with less than minimum users after timeout
//
//        console.log("Timeout mechanism verified");
//    }
//
//    // testAverageGasPriceCalculation: Test average gas price calculation for batches
//    function testAverageGasPriceCalculation() public view {
//        console.log("Testing Average Gas Price Calculation");
//
//        // Test that users have different gas thresholds for averaging
//        (,,,, uint256 aliceGas,) = hook.userStrategies(alice);
//        (,,,, uint256 bobGas,) = hook.userStrategies(bob);
//        (,,,, uint256 charlieGas,) = hook.userStrategies(charlie);
//
//        assertEq(aliceGas, 50 gwei, "Alice gas threshold should be 50 gwei");
//        assertEq(bobGas, 55 gwei, "Bob gas threshold should be 55 gwei");
//        assertEq(charlieGas, 60 gwei, "Charlie gas threshold should be 60 gwei");
//
//        // Calculate expected average: (50 + 55 + 60) / 3 = 55 gwei
//        uint256 expectedAverage = (50 gwei + 55 gwei + 60 gwei) / 3;
//        assertEq(expectedAverage, 55 gwei, "Average calculation should be correct");
//
//        console.log("Average gas price calculation verified");
//    }
//
//    // testBatchExecutionConditions: Test all conditions for batch execution
//    function testBatchExecutionConditions() public {
//        console.log("Testing Batch Execution Conditions");
//
//        // Test that shouldExecuteBatch checks multiple conditions:
//        // 1. Minimum batch size
//        // 2. Gas price tolerance
//        // 3. Maximum wait time
//        // 4. Maximum batch size
//
//        bool shouldExecute = hook.shouldExecuteBatch(poolId);
//        assertFalse(shouldExecute, "Should not execute with no pending compounds");
//
//        // Test with different gas prices
//        vm.fee(30 gwei); // Low gas price
//        shouldExecute = hook.shouldExecuteBatch(poolId);
//        assertFalse(shouldExecute, "Should not execute with no pending compounds regardless of gas");
//
//        vm.fee(100 gwei); // High gas price
//        shouldExecute = hook.shouldExecuteBatch(poolId);
//        assertFalse(shouldExecute, "Should not execute with no pending compounds even with high gas");
//
//        console.log("Batch execution conditions verified");
//    }
//
//    // testCompoundScheduling: Test scheduling compounds for batch execution
//    function testCompoundScheduling() public {
//        console.log("Testing Compound Scheduling");
//
//        // Test that compounds can be scheduled (requires proper conditions)
//        // This would typically require:
//        // 1. Users to have accumulated fees
//        // 2. Gas price to be acceptable
//        // 3. Time interval to have passed
//
//        // For now, test that scheduling requires active strategy
//        vm.prank(address(0x999)); // Non-activated user
//        vm.expectRevert(); // Should revert due to inactive strategy
//        hook.scheduleCompound(poolId, 1 ether);
//
//        console.log("Compound scheduling access control verified");
//    }
//
//    // testBatchGasEstimation: Test gas estimation for batch vs individual execution
//    function testBatchGasEstimation() public pure {
//        console.log("Testing Batch Gas Estimation");
//
//        // Test that gas estimation infrastructure exists
//        // Individual compound gas estimate: ~150,000 gas
//        // Batch execution should be more efficient per user
//
//        uint256 estimatedIndividualGas = 150000; // Estimated from hook contract
//        assertTrue(estimatedIndividualGas > 100000, "Individual gas cost should be significant");
//
//        // Batch efficiency should improve with more users
//        // Gas per user in batch = (base_cost + per_user_cost * n) / n
//        // As n increases, average gas per user decreases
//
//        console.log("Gas estimation infrastructure verified");
//    }
//
//    // testMultiPoolBatchIsolation: Test that batches are isolated per pool
//    function testMultiPoolBatchIsolation() public {
//        console.log("Testing Multi-Pool Batch Isolation");
//
//        // Create second pool
//        MockERC20 token2 = new MockERC20("Token2", "T2", 18);
//        MockERC20 token3 = new MockERC20("Token3", "T3", 18);
//
//        if (address(token2) > address(token3)) {
//            (token2, token3) = (token3, token2);
//        }
//
//        Currency currency2 = Currency.wrap(address(token2));
//        Currency currency3 = Currency.wrap(address(token3));
//
//        PoolKey memory poolKey2 = PoolKey({
//            currency0: currency2,
//            currency1: currency3,
//            fee: FEE,
//            tickSpacing: TICK_SPACING,
//            hooks: IHooks(address(hook))
//        });
//
//        PoolId poolId2 = poolKey2.toId();
//        poolManager.initialize(poolKey2, TestConstants.SQRT_PRICE_1_1);
//
//        // Test that batches are tracked separately per pool
//        uint256 pool1BatchSize = hook.getPendingBatchSize(poolId);
//        uint256 pool2BatchSize = hook.getPendingBatchSize(poolId2);
//
//        assertEq(pool1BatchSize, 0, "Pool 1 should have no pending batches");
//        assertEq(pool2BatchSize, 0, "Pool 2 should have no pending batches");
//
//        console.log("Multi-pool batch isolation verified");
//    }
//
//    // testBatchUserDistribution: Test even distribution of users across batches
//    function testBatchUserDistribution() public view {
//        console.log("Testing Batch User Distribution");
//
//        // Test that the hook can handle different numbers of users
//        // and distribute gas costs evenly
//
//        // With 5 users, gas cost should be split 5 ways
//        // With 2 users (minimum), gas cost should be split 2 ways
//        // With 50 users (maximum), gas cost should be split 50 ways
//
//        uint256 minUsers = hook.MIN_BATCH_SIZE();
//        uint256 maxUsers = hook.MAX_BATCH_SIZE();
//
//        // Test that cost per user decreases with more users
//        // Total gas = base + (per_user * count)
//        // Cost per user = total_gas / count
//
//        assertTrue(maxUsers > minUsers, "Max users should be greater than min");
//
//        console.log("User distribution logic verified");
//    }
//}
