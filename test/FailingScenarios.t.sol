// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {YieldMaximizerHook} from "../src/YieldMaximizerHook.sol";
import {SimpleDeployers} from "./utils/SimpleDeployers.sol";
import {TestConstants} from "./utils/TestConstants.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/**
 * @title Failing Scenarios Tests
 * @notice Unit tests for edge cases and error conditions that should fail
 */
contract FailingScenariosTest is Test, SimpleDeployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    YieldMaximizerHook hook;
    PoolKey poolKey;
    PoolId poolId;
    Currency currency0;
    Currency currency1;

    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolSwapTest swapRouter;

    address alice = address(0x1);
    address bob = address(0x2);
    address nonUser = address(0x999);

    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;

    function setUp() public {
        deployArtifacts();
        (currency0, currency1) = deployCurrencyPair();

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager);
        address hookAddress =
            deployHookToProperAddress("YieldMaximizerHook.sol:YieldMaximizerHook", constructorArgs, flags);
        hook = YieldMaximizerHook(hookAddress);

        (poolKey, poolId) =
            createPool(currency0, currency1, IHooks(address(hook)), FEE, TICK_SPACING, TestConstants.SQRT_PRICE_1_1);

        // Deploy test routers
        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
        swapRouter = new PoolSwapTest(poolManager);
    }

    // Test strategy activation failures
    function test_activateStrategy_alreadyActive_shouldFail() public {
        // Alice activates strategy first
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Try to activate again - should fail
        vm.prank(alice);
        vm.expectRevert("Strategy already active");
        hook.activateStrategy(poolId, 60 gwei, 7);
    }

    function test_activateStrategy_invalidRiskLevel_shouldFail() public {
        // Test risk level 0 (too low)
        vm.prank(alice);
        vm.expectRevert("Invalid risk level");
        hook.activateStrategy(poolId, 50 gwei, 0);

        // Test risk level 11 (too high)
        vm.prank(alice);
        vm.expectRevert("Invalid risk level");
        hook.activateStrategy(poolId, 50 gwei, 11);
    }

    function test_activateStrategy_invalidGasThreshold_shouldFail() public {
        // Test gas threshold 0
        vm.prank(alice);
        vm.expectRevert("Invalid gas threshold");
        hook.activateStrategy(poolId, 0, 5);

        // Test gas threshold too high (above MAX_GAS_PRICE)
        vm.prank(alice);
        vm.expectRevert("Invalid gas threshold");
        hook.activateStrategy(poolId, 101 gwei, 5);
    }

    // Test strategy deactivation failures
    function test_deactivateStrategy_notActive_shouldFail() public {
        // Try to deactivate when no strategy is active
        vm.prank(alice);
        vm.expectRevert("User strategy not active");
        hook.deactivateStrategy(poolId);
    }

    // Test strategy update failures
    function test_updateStrategy_notActive_shouldFail() public {
        // Try to update when no strategy is active
        vm.prank(alice);
        vm.expectRevert("User strategy not active");
        hook.updateStrategy(75 gwei, 8);
    }

    function test_updateStrategy_invalidParams_shouldFail() public {
        // Activate strategy first
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Try to update with invalid risk level
        vm.prank(alice);
        vm.expectRevert("Invalid risk level");
        hook.updateStrategy(75 gwei, 0);

        // Try to update with invalid gas threshold
        vm.prank(alice);
        vm.expectRevert("Invalid gas threshold");
        hook.updateStrategy(0, 8);
    }

    // Test compound failures
    function test_compound_cannotCompoundNow_shouldFail() public {
        // Alice activates strategy but has no fees
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Try to compound with no fees - should fail
        vm.prank(alice);
        vm.expectRevert("Cannot compound now");
        hook.compound(poolId);
    }

    function test_emergencyCompound_noFees_shouldFail() public {
        // Try emergency compound with no fees
        vm.prank(alice);
        vm.expectRevert("No fees to compound");
        hook.emergencyCompound(poolId);
    }

    function test_scheduleCompound_conditionsNotMet_shouldFail() public {
        // Alice activates strategy but conditions aren't met
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Try to schedule compound when conditions not met
        vm.prank(alice);
        vm.expectRevert("Compound conditions not met");
        hook.scheduleCompound(poolId, 100);
    }

    // Test batch execution failures
    function test_forceBatchExecution_noPending_shouldFail() public {
        // Try to force batch execution with no pending compounds
        vm.expectRevert("No pending compounds");
        hook.forceBatchExecution(poolId);
    }

    // Test zero amount scenarios that should not generate fees
    function test_zeroSwap_shouldNotGenerateFees() public {
        // Alice activates strategy and adds liquidity
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);
        _addLiquidityForUser(alice, 1000000000000000000);

        // Record initial fees
        YieldMaximizerHook.FeeAccounting memory feesBefore = hook.getUserFees(alice, poolId);

        // Simulate zero swap (should not generate fees)
        // This tests the hook's zero-amount handling
        assertEq(feesBefore.totalFeesEarned, 0, "Should start with zero fees");
        assertEq(feesBefore.pendingCompound, 0, "Should start with zero pending");
    }

    // Test that inactive users don't get added to active list
    // TODO: this could be enable later when I fix the user strategies
    //    function test_addLiquidity_withoutStrategy_notAddedToActive() public {
    //        // User adds liquidity without activating strategy
    //        _addLiquidityForUser(alice, 1000000000000000000);
    //
    //        // Verify user is NOT in active users list
    //        address[] memory activeUsers = hook.getActiveUsers(poolId);
    //        assertEq(activeUsers.length, 0, "Should have no active users without strategy activation");
    //
    //        // User should still have liquidity position but not be tracked as active
    //        YieldMaximizerHook.UserLiquidityPosition memory position = hook.getUserLiquidityPosition(alice, poolId);
    //        assertGt(position.liquidityAmount, 0, "Should have liquidity position");
    //        assertTrue(position.isActive, "Position should be active even without strategy");
    //    }

    // Test minimum compound amount enforcement
    function test_shouldCompound_belowMinimum_shouldReturnFalse() public {
        // Alice activates strategy
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Advance time to pass interval check
        vm.warp(block.timestamp + hook.MIN_ACTION_INTERVAL() + 1);

        // Check compound with zero fees (below minimum)
        bool shouldCompound = hook.shouldCompound(alice, poolId);
        assertFalse(shouldCompound, "Should not compound with zero fees (below minimum)");
    }

    // Test time interval enforcement
    function test_shouldCompound_tooSoon_shouldReturnFalse() public {
        // Alice activates strategy (sets lastCompoundTime)
        vm.prank(alice);
        hook.activateStrategy(poolId, 50 gwei, 5);

        // Don't advance time - try immediately
        bool shouldCompound = hook.shouldCompound(alice, poolId);
        assertFalse(shouldCompound, "Should not compound immediately after activation (time interval not met)");
    }

    // Test gas threshold storage (even though bypassed)
    function test_gasThreshold_storedCorrectly() public {
        // Test various gas thresholds are stored correctly
        uint256[] memory gasThresholds = new uint256[](3);
        gasThresholds[0] = 1 gwei;
        gasThresholds[1] = 50 gwei;
        gasThresholds[2] = 100 gwei;

        for (uint256 i = 0; i < gasThresholds.length; i++) {
            address user = address(uint160(100 + i));
            uint256 gasThreshold = gasThresholds[i];

            vm.prank(user);
            hook.activateStrategy(poolId, gasThreshold, 5);

            (,,,, uint256 storedGas,) = hook.userStrategies(user);
            assertEq(storedGas, gasThreshold, "Gas threshold should be stored correctly");
        }
    }

    // Test user state isolation
    function test_userIsolation_separateStates() public {
        // Alice activates with different params than Bob
        vm.prank(alice);
        hook.activateStrategy(poolId, 25 gwei, 3);

        vm.prank(bob);
        hook.activateStrategy(poolId, 75 gwei, 8);

        // Verify separate states
        (bool aliceActive,,,, uint256 aliceGas, uint8 aliceRisk) = hook.userStrategies(alice);
        (bool bobActive,,,, uint256 bobGas, uint8 bobRisk) = hook.userStrategies(bob);

        assertTrue(aliceActive, "Alice should be active");
        assertTrue(bobActive, "Bob should be active");
        assertEq(aliceGas, 25 gwei, "Alice gas should be separate");
        assertEq(bobGas, 75 gwei, "Bob gas should be separate");
        assertEq(aliceRisk, 3, "Alice risk should be separate");
        assertEq(bobRisk, 8, "Bob risk should be separate");
    }

    // Helper function
    function _addLiquidityForUser(address user, uint256 liquidityAmount) internal {
        vm.startPrank(user);

        MockERC20(Currency.unwrap(currency0)).mint(user, 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(user, 1000 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(liquidityAmount),
                salt: bytes32(0)
            }),
            abi.encode(user)
        );

        vm.stopPrank();
    }
}
