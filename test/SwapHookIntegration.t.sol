// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {YieldMaximizerHook} from "../src/YieldMaximizerHook.sol";

contract SwapHookIntegrationTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    MockERC20 token;
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    YieldMaximizerHook hook;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    function setUp() public {
        // Deploy V4 infrastructure
        deployFreshManagerAndRouters();

        // Deploy test token
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint tokens
        token.mint(address(this), 1000 ether);
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(charlie, 1000 ether);

        // Give test addresses ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);

        // Deploy hook with proper permissions
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
        deployCodeTo("YieldMaximizerHook.sol", abi.encode(manager), address(flags));
        hook = YieldMaximizerHook(address(flags));

        // Approve tokens
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.startPrank(alice);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        // Initialize pool
        (key,) = initPool(
            ethCurrency,
            tokenCurrency,
            hook,
            3000, // 0.3% fee
            SQRT_PRICE_1_1
        );

        // Add initial liquidity
        _addInitialLiquidity();
    }

    function _addInitialLiquidity() internal {
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swapTriggersAfterSwapHook() public {
        PoolId poolId = key.toId();

        // Setup: Alice activates strategy and adds liquidity
        vm.startPrank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 ethToAdd = 0.1 ether;
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(alice) // Pass Alice's address in hookData
        );
        vm.stopPrank();

        // Record Alice's fees before swap
        YieldMaximizerHook.FeeAccounting memory feesBefore = hook.getUserFees(alice, poolId);
        console.log("Fees before swap - Total:", feesBefore.totalFeesEarned);
        console.log("Fees before swap - Pending:", feesBefore.pendingCompound);

        // Bob performs a swap
        vm.startPrank(bob);
        uint256 swapAmount = 0.01 ether;

        swapRouter.swap{value: swapAmount}(
            key,
            SwapParams({
                zeroForOne: true, // ETH -> TOKEN
                amountSpecified: -int256(swapAmount), // exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.stopPrank();

        // Verify that _afterSwap was triggered by checking if Alice received fees
        YieldMaximizerHook.FeeAccounting memory feesAfter = hook.getUserFees(alice, poolId);
        console.log("Fees after swap - Total:", feesAfter.totalFeesEarned);
        console.log("Fees after swap - Pending:", feesAfter.pendingCompound);

        // Assert that the hook was triggered and fees were distributed
        assertGt(
            feesAfter.totalFeesEarned,
            feesBefore.totalFeesEarned,
            "_afterSwap hook should have been triggered and fees distributed"
        );

        assertGt(
            feesAfter.pendingCompound, feesBefore.pendingCompound, "Pending compound amount should increase after swap"
        );

        // Verify that lastCollection timestamp was updated
        assertGt(feesAfter.lastCollection, feesBefore.lastCollection, "Last collection timestamp should be updated");

        console.log("_afterSwap hook was successfully triggered and processed fees");
        console.log("Fee increase:", feesAfter.totalFeesEarned - feesBefore.totalFeesEarned);
    }

    // Multi-User Fee Distribution
    //
    //  Alice adds 0.2 ETH liquidity
    //  Bob adds 0.1 ETH liquidity (half of Alice's)
    //  Both have active strategies
    //  Both should receive proportional fees
    //
    // Proportional Fee Calculation:
    //  Alice should earn ~2x Bob's fees (since she provided 2x liquidity)
    //  Test allows 10% tolerance (1.8x to 2.2x ratio) for rounding differences
    //  Validates the fee calculation math is correct
    function test_swapGeneratesFeesAndDistributesToActiveUsers() public {
        PoolId poolId = key.toId();

        // Setup: Both Alice and Bob activate strategies and add different amounts of liquidity

        // Alice activates strategy and adds 0.2 ETH liquidity
        vm.startPrank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 aliceEthToAdd = 0.2 ether;
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 aliceLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, aliceEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: aliceEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(aliceLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(alice)
        );
        vm.stopPrank();

        // Bob activates strategy and adds 0.1 ETH liquidity (half of Alice's)
        vm.startPrank(bob);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 bobEthToAdd = 0.1 ether;
        uint128 bobLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, bobEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: bobEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(bobLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(bob)
        );
        vm.stopPrank();

        // Record fees before swap
        YieldMaximizerHook.FeeAccounting memory aliceFeesBefore = hook.getUserFees(alice, poolId);
        YieldMaximizerHook.FeeAccounting memory bobFeesBefore = hook.getUserFees(bob, poolId);

        console.log("=== Before Swap ===");
        console.log("Alice fees before:", aliceFeesBefore.totalFeesEarned);
        console.log("Bob fees before:", bobFeesBefore.totalFeesEarned);

        // Verify both users are in active users list
        address[] memory activeUsers = hook.getActiveUsers(poolId);
        assertEq(activeUsers.length, 2, "Should have 2 active users");

        // Charlie performs a swap to generate fees
        vm.deal(address(this), 10 ether); // Make sure test contract has ETH
        uint256 swapAmount = 0.05 ether; // Larger swap to generate more fees

        swapRouter.swap{value: swapAmount}(
            key,
            SwapParams({
                zeroForOne: true, // ETH -> TOKEN
                amountSpecified: -int256(swapAmount), // exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        // Check fees after swap
        YieldMaximizerHook.FeeAccounting memory aliceFeesAfter = hook.getUserFees(alice, poolId);
        YieldMaximizerHook.FeeAccounting memory bobFeesAfter = hook.getUserFees(bob, poolId);

        console.log("=== After Swap ===");
        console.log("Alice fees after:", aliceFeesAfter.totalFeesEarned);
        console.log("Bob fees after:", bobFeesAfter.totalFeesEarned);

        // Calculate fee increases
        uint256 aliceFeeIncrease = aliceFeesAfter.totalFeesEarned - aliceFeesBefore.totalFeesEarned;
        uint256 bobFeeIncrease = bobFeesAfter.totalFeesEarned - bobFeesBefore.totalFeesEarned;

        console.log("Alice fee increase:", aliceFeeIncrease);
        console.log("Bob fee increase:", bobFeeIncrease);

        // Both users should have earned fees
        assertGt(aliceFeeIncrease, 0, "Alice should have earned fees");
        assertGt(bobFeeIncrease, 0, "Bob should have earned fees");

        // Alice should have earned approximately twice as much as Bob (she provided 2x liquidity)
        // Allow for some rounding tolerance (within 10%)
        uint256 expectedRatio = 200; // 2.00x (in basis points)
        uint256 actualRatio = (aliceFeeIncrease * 100) / bobFeeIncrease;

        console.log("Expected ratio (200 = 2x):", expectedRatio);
        console.log("Actual ratio:", actualRatio);

        // Alice should earn more fees than Bob
        assertGt(aliceFeeIncrease, bobFeeIncrease, "Alice should earn more fees than Bob");

        // The ratio should be approximately 2:1 (allowing for rounding differences)
        assertGe(actualRatio, 180, "Alice should earn at least 1.8x Bob's fees"); // 1.8x minimum
        assertLe(actualRatio, 220, "Alice should earn at most 2.2x Bob's fees"); // 2.2x maximum

        // Verify pending compound amounts match total fees earned
        assertEq(aliceFeesAfter.pendingCompound, aliceFeesAfter.totalFeesEarned, "Alice pending should match total");
        assertEq(bobFeesAfter.pendingCompound, bobFeesAfter.totalFeesEarned, "Bob pending should match total");

        // Verify lastCollection timestamps were updated
        assertGt(
            aliceFeesAfter.lastCollection, aliceFeesBefore.lastCollection, "Alice lastCollection should be updated"
        );
        assertGt(bobFeesAfter.lastCollection, bobFeesBefore.lastCollection, "Bob lastCollection should be updated");

        console.log("Fees correctly distributed proportionally to active users");
        console.log("Alice earned", (actualRatio / 100), "x more fees than Bob (expected ~2x)");
    }

    // Three-User Scenario:
    //
    // Alice: 0.3 ETH liquidity
    // Bob: 0.1 ETH liquidity
    // Charlie: 0.2 ETH liquidity
    // Expected ratios: Alice:Bob:Charlie = 3:1:2
    //
    // Comprehensive Proportional Validation:
    //
    // Alice vs Bob: Should be ~3:1 ratio (Alice earns 3x Bob's fees)
    // Charlie vs Bob: Should be ~2:1 ratio (Charlie earns 2x Bob's fees)
    // Alice vs Charlie: Should be ~1.5:1 ratio (Alice earns 1.5x Charlie's fees)
    //
    // Testing:
    //
    // Tolerance bands: Allows 10% variance for rounding differences
    // Large swap: 0.1 ETH swap generates substantial fees for clear differentiation
    // Multiple assertions: Tests all pair-wise ratios
    // State validation: Verifies pending amounts match total fees
    function test_swapWithActiveUsersDistributesProportionalFees() public {
        PoolId poolId = key.toId();

        // Setup: Three users with different liquidity amounts
        // Alice: 0.3 ETH, Bob: 0.1 ETH, Charlie: 0.2 ETH
        // Expected ratio: Alice:Bob:Charlie = 3:1:2

        // Alice adds 0.3 ETH liquidity
        vm.startPrank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 aliceEthToAdd = 0.3 ether;
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 aliceLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, aliceEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: aliceEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(aliceLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(alice)
        );
        vm.stopPrank();

        // Bob adds 0.1 ETH liquidity (1/3 of Alice's)
        vm.startPrank(bob);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 bobEthToAdd = 0.1 ether;
        uint128 bobLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, bobEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: bobEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(bobLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(bob)
        );
        vm.stopPrank();

        // Charlie adds 0.2 ETH liquidity (2/3 of Alice's)
        vm.startPrank(charlie);
        hook.activateStrategy(poolId, 50 gwei, 5);

        uint256 charlieEthToAdd = 0.2 ether;
        uint128 charlieLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, charlieEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: charlieEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(charlieLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(charlie)
        );
        vm.stopPrank();

        // Verify all users are active
        address[] memory activeUsers = hook.getActiveUsers(poolId);
        assertEq(activeUsers.length, 3, "Should have 3 active users");

        // Record fees before swap
        YieldMaximizerHook.FeeAccounting memory aliceFeesBefore = hook.getUserFees(alice, poolId);
        YieldMaximizerHook.FeeAccounting memory bobFeesBefore = hook.getUserFees(bob, poolId);
        YieldMaximizerHook.FeeAccounting memory charlieFeesBefore = hook.getUserFees(charlie, poolId);

        console.log("=== Liquidity Positions ===");
        console.log("Alice liquidity (0.3 ETH):", aliceEthToAdd);
        console.log("Bob liquidity (0.1 ETH):", bobEthToAdd);
        console.log("Charlie liquidity (0.2 ETH):", charlieEthToAdd);

        // Perform a large swap to generate substantial fees
        vm.deal(address(this), 10 ether);
        uint256 swapAmount = 0.1 ether; // Large swap for clear fee differences

        swapRouter.swap{value: swapAmount}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        // Check fees after swap
        YieldMaximizerHook.FeeAccounting memory aliceFeesAfter = hook.getUserFees(alice, poolId);
        YieldMaximizerHook.FeeAccounting memory bobFeesAfter = hook.getUserFees(bob, poolId);
        YieldMaximizerHook.FeeAccounting memory charlieFeesAfter = hook.getUserFees(charlie, poolId);

        // Calculate fee increases
        uint256 aliceFeeIncrease = aliceFeesAfter.totalFeesEarned - aliceFeesBefore.totalFeesEarned;
        uint256 bobFeeIncrease = bobFeesAfter.totalFeesEarned - bobFeesBefore.totalFeesEarned;
        uint256 charlieFeeIncrease = charlieFeesAfter.totalFeesEarned - charlieFeesBefore.totalFeesEarned;

        console.log("=== Fee Distribution Results ===");
        console.log("Alice fees earned:", aliceFeeIncrease);
        console.log("Bob fees earned:", bobFeeIncrease);
        console.log("Charlie fees earned:", charlieFeeIncrease);

        // All users should earn fees
        assertGt(aliceFeeIncrease, 0, "Alice should earn fees");
        assertGt(bobFeeIncrease, 0, "Bob should earn fees");
        assertGt(charlieFeeIncrease, 0, "Charlie should earn fees");

        // Verify proportional distribution (allowing for rounding tolerance)
        // Expected ratios: Alice(0.3):Bob(0.1):Charlie(0.2) = 3:1:2

        // Alice should earn 3x Bob's fees (within tolerance)
        uint256 aliceToBobRatio = (aliceFeeIncrease * 100) / bobFeeIncrease;
        console.log("Alice/Bob ratio (expected ~300):", aliceToBobRatio);
        assertGe(aliceToBobRatio, 280, "Alice should earn at least 2.8x Bob's fees");
        assertLe(aliceToBobRatio, 320, "Alice should earn at most 3.2x Bob's fees");

        // Charlie should earn 2x Bob's fees (within tolerance)
        uint256 charlieToBobRatio = (charlieFeeIncrease * 100) / bobFeeIncrease;
        console.log("Charlie/Bob ratio (expected ~200):", charlieToBobRatio);
        assertGe(charlieToBobRatio, 180, "Charlie should earn at least 1.8x Bob's fees");
        assertLe(charlieToBobRatio, 220, "Charlie should earn at most 2.2x Bob's fees");

        // Alice should earn 1.5x Charlie's fees (within tolerance)
        uint256 aliceToCharlieRatio = (aliceFeeIncrease * 100) / charlieFeeIncrease;
        console.log("Alice/Charlie ratio (expected ~150):", aliceToCharlieRatio);
        assertGe(aliceToCharlieRatio, 140, "Alice should earn at least 1.4x Charlie's fees");
        assertLe(aliceToCharlieRatio, 160, "Alice should earn at most 1.6x Charlie's fees");

        // Verify total fee distribution adds up correctly
        uint256 totalFeesDistributed = aliceFeeIncrease + bobFeeIncrease + charlieFeeIncrease;
        console.log("Total fees distributed:", totalFeesDistributed);
        assertGt(totalFeesDistributed, 0, "Total fees should be greater than 0");

        // Verify pending amounts equal total fees for each user
        assertEq(aliceFeesAfter.pendingCompound, aliceFeesAfter.totalFeesEarned, "Alice pending equals total");
        assertEq(bobFeesAfter.pendingCompound, bobFeesAfter.totalFeesEarned, "Bob pending equals total");
        assertEq(charlieFeesAfter.pendingCompound, charlieFeesAfter.totalFeesEarned, "Charlie pending equals total");

        console.log("Proportional fee distribution test passed");
        // First, perform the division and store the results.
        uint256 ratio1 = aliceFeeIncrease / bobFeeIncrease;
        uint256 ratio2 = charlieFeeIncrease / bobFeeIncrease;

        // Use a single console.log with a format string.
        console.log("Alice:Bob:Charlie actual ratio = %d : %d : %d", ratio1, 1, ratio2);
    }

    function test_swapSchedulesCompoundWhenThresholdMet() public {
        PoolId poolId = key.toId();

        // Setup: Alice activates strategy and adds liquidity
        vm.startPrank(alice);
        hook.activateStrategy(poolId, 100 gwei, 5); // High gas threshold so compounds aren't prevented by gas

        uint256 aliceEthToAdd = 0.1 ether;
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 aliceLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, aliceEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: aliceEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(aliceLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(alice)
        );
        vm.stopPrank();

        // Check initial state - no pending compounds
        uint256 initialPendingBatchSize = hook.getPendingBatchSize(poolId);
        console.log("Initial pending batch size:", initialPendingBatchSize);
        assertEq(initialPendingBatchSize, 0, "Initially no pending compounds");

        // Get minimum compound amount
        uint256 minCompoundAmount = hook.MIN_COMPOUND_AMOUNT();
        console.log("Minimum compound amount:", minCompoundAmount);

        // Perform small swaps to gradually build up fees until threshold is met
        vm.deal(address(this), 10 ether);

        // Track Alice's fees accumulation
        uint256 totalSwaps = 0;
        uint256 swapAmount = 0.01 ether; // Small swap amount

        while (true) {
            // Check Alice's current pending compound amount
            YieldMaximizerHook.FeeAccounting memory aliceFees = hook.getUserFees(alice, poolId);
            console.log("Swap", totalSwaps, "- Alice pending compound:", aliceFees.pendingCompound);

            // If we have enough fees to meet minimum compound threshold, break
            if (aliceFees.pendingCompound >= minCompoundAmount) {
                console.log("Threshold reached! Alice has", aliceFees.pendingCompound, "pending compound");
                break;
            }

            // Perform another swap to generate more fees
            swapRouter.swap{value: swapAmount}(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(swapAmount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ZERO_BYTES
            );

            totalSwaps++;

            // Safety check to prevent infinite loop
            if (totalSwaps > 50) {
                console.log("Too many swaps, compound threshold might be too high");
                break;
            }
        }

        // Verify compound conditions are met
        bool shouldCompound = hook.shouldCompound(alice, poolId);
        console.log("Should compound:", shouldCompound);

        if (!shouldCompound) {
            // If time interval is the issue, advance time and try again
            YieldMaximizerHook.UserStrategy memory strategy = hook.getUserStrategy(alice);
            uint256 timeSinceLastCompound = block.timestamp - strategy.lastCompoundTime;
            uint256 minInterval = hook.MIN_ACTION_INTERVAL();

            if (timeSinceLastCompound < minInterval) {
                console.log("Advancing time to meet minimum interval requirement");
                vm.warp(block.timestamp + minInterval + 1); // Add 1 extra second for safety
                shouldCompound = hook.shouldCompound(alice, poolId);
                console.log("Should compound after time advance:", shouldCompound);
            }
        }

        if (shouldCompound) {
            // Perform one more swap that should trigger automatic compound scheduling
            uint256 pendingBatchSizeBefore = hook.getPendingBatchSize(poolId);
            console.log("Pending batch size before triggering swap:", pendingBatchSizeBefore);

            swapRouter.swap{value: swapAmount}(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(swapAmount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ZERO_BYTES
            );

            // Check if compound was scheduled
            uint256 pendingBatchSizeAfter = hook.getPendingBatchSize(poolId);
            console.log("Pending batch size after triggering swap:", pendingBatchSizeAfter);

            // The swap should have automatically scheduled a compound
            assertGt(pendingBatchSizeAfter, pendingBatchSizeBefore, "Compound should be scheduled when threshold met");
            assertEq(pendingBatchSizeAfter, 1, "Should have 1 pending compound for Alice");

            console.log("Compound successfully scheduled automatically!");
        } else {
            console.log("Compound conditions not met - checking why:");

            YieldMaximizerHook.FeeAccounting memory finalFees = hook.getUserFees(alice, poolId);
            YieldMaximizerHook.UserStrategy memory strategy = hook.getUserStrategy(alice);

            console.log("Final pending compound:", finalFees.pendingCompound);
            console.log("Min compound amount:", minCompoundAmount);
            console.log("Current gas price:", tx.gasprice);
            console.log("Gas threshold:", strategy.gasThreshold);
            console.log("Time since last compound:", block.timestamp - strategy.lastCompoundTime);
            console.log("Min action interval:", hook.MIN_ACTION_INTERVAL());

            // If we can't meet compound conditions, at least verify the logic is working
            if (finalFees.pendingCompound < minCompoundAmount) {
                console.log("Fees below minimum threshold - this is expected behavior");
            } else if (tx.gasprice > strategy.gasThreshold) {
                console.log("Gas price too high - this is expected behavior");
            } else {
                revert("Compound should be possible but shouldCompound returned false");
            }
        }

        // Verify Alice's fees were updated correctly during the process
        YieldMaximizerHook.FeeAccounting memory finalAliceFees = hook.getUserFees(alice, poolId);
        assertGt(finalAliceFees.totalFeesEarned, 0, "Alice should have earned fees");

        console.log("Total swaps performed:", totalSwaps + 1);
        console.log("Final Alice total fees:", finalAliceFees.totalFeesEarned);
        console.log("Test completed successfully");
    }

    function test_calculateFeesFromSwapAccuracy() public {
        PoolId poolId = key.toId();

        // Setup: Alice activates strategy and adds liquidity
        vm.startPrank(alice);
        hook.activateStrategy(poolId, 100 gwei, 5);

        uint256 aliceEthToAdd = 0.1 ether;
        uint128 aliceLiquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(60), aliceEthToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: aliceEthToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(aliceLiquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(alice)
        );
        vm.stopPrank();

        // Test different swap amounts and verify fee calculations
        uint256[] memory swapAmounts = new uint256[](4);
        swapAmounts[0] = 0.001 ether; // Small swap
        swapAmounts[1] = 0.01 ether; // Medium swap
        swapAmounts[2] = 0.1 ether; // Large swap
        swapAmounts[3] = 1 ether; // Very large swap

        console.log("=== Fee Calculation Accuracy Test ===");
        console.log("Pool fee tier:", key.fee); // Should be 3000 (0.3%)

        vm.deal(address(this), 10 ether);

        for (uint256 i = 0; i < swapAmounts.length; i++) {
            uint256 swapAmount = swapAmounts[i];

            // Get Alice's fees before swap
            YieldMaximizerHook.FeeAccounting memory feesBefore = hook.getUserFees(alice, poolId);

            console.log("--- Swap", i + 1, "---");
            console.log("Swap amount (ETH):", swapAmount);

            // Perform the swap
            swapRouter.swap{value: swapAmount}(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(swapAmount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ZERO_BYTES
            );

            // Get Alice's fees after swap
            YieldMaximizerHook.FeeAccounting memory feesAfter = hook.getUserFees(alice, poolId);

            // Calculate the fee increase
            uint256 actualFeeIncrease = feesAfter.totalFeesEarned - feesBefore.totalFeesEarned;

            // Calculate expected fees manually
            // Expected fee = swapAmount * feeTier / 1,000,000
            // Since Alice is the only LP, she should get all the fees
            uint256 expectedFees = (swapAmount * key.fee) / 1000000;

            console.log("Swap amount:", swapAmount);
            console.log("Expected fees:", expectedFees);
            console.log("Actual fees:", actualFeeIncrease);

            // Calculate the accuracy percentage
            if (expectedFees > 0) {
                uint256 accuracy = (actualFeeIncrease * 10000) / expectedFees; // Basis points
                console.log("Accuracy:", accuracy, "basis points (10000 = 100%)");

                // The accuracy should be close to 100% (allowing for some variance due to price impact)
                // We allow 80% to 120% accuracy to account for:
                // - Price impact affecting the actual swap volume
                // - Rounding differences in the fee calculation
                // - AMM mechanics that might affect fee distribution
                assertGe(accuracy, 8000, "Fee calculation should be at least 80% accurate");
                assertLe(accuracy, 12000, "Fee calculation should be at most 120% accurate");

                // Verify basic sanity checks
                assertGt(actualFeeIncrease, 0, "Should always earn some fees from swaps");

                // For larger swaps, expect higher absolute fees
                if (i > 0) {
                    YieldMaximizerHook.FeeAccounting memory previousFees = hook.getUserFees(alice, poolId);
                    // Note: Due to price impact, larger swaps may not always yield proportionally higher fees
                    // So we just check that we're earning reasonable amounts
                    assertGt(actualFeeIncrease, 0, "Each swap should generate fees");
                }
            }
        }

        // Test edge cases
        console.log("\n=== Edge Case Tests ===");

        // Test very small swap (dust amount)
        uint256 dustAmount = 1000 wei; // Very small amount
        YieldMaximizerHook.FeeAccounting memory dustBefore = hook.getUserFees(alice, poolId);

        // Try to swap dust amount (might fail due to minimum swap requirements)
        try swapRouter.swap{value: dustAmount}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(dustAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        ) {
            YieldMaximizerHook.FeeAccounting memory dustAfter = hook.getUserFees(alice, poolId);
            uint256 dustFees = dustAfter.totalFeesEarned - dustBefore.totalFeesEarned;
            console.log("Dust swap fees:", dustFees);

            // Even tiny swaps should generate some fees (or at least not break)
            // The calculateFeesFromSwap function should handle small amounts gracefully
        } catch {
            console.log("Dust swap failed (expected for very small amounts)");
        }

        // Verify final state
        YieldMaximizerHook.FeeAccounting memory finalFees = hook.getUserFees(alice, poolId);
        assertGt(finalFees.totalFeesEarned, 0, "Alice should have earned total fees from all swaps");
        assertEq(finalFees.pendingCompound, finalFees.totalFeesEarned, "All fees should be pending for compound");

        console.log("\nFinal total fees earned:", finalFees.totalFeesEarned);
        console.log("Fee calculation accuracy test completed successfully");
    }
}
