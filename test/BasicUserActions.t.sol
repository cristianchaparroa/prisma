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
//import {SwapParams} from "v4-core/types/PoolOperation.sol";
//import {TickMath} from "v4-core/libraries/TickMath.sol";
//import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
//
///**
// * @title Comprehensive BasicUserTest
// * @notice Real Uniswap V4 integration tests covering all functionality
// */
//contract BasicUserTest is Test, SimpleDeployers {
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
//    // Pool parameters
//    uint24 constant FEE = 3000; // 0.3%
//    int24 constant TICK_SPACING = 60;
//    uint160 constant SQRT_PRICE_1_1 = TestConstants.SQRT_PRICE_1_1;
//
//    function setUp() public {
//        // Deploy the full V4 infrastructure properly
//        deployArtifacts();
//
//        // Deploy currency pair
//        (currency0, currency1) = deployCurrencyPair();
//
//        // Calculate hook address with proper permissions
//        uint160 flags = uint160(
//            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
//                | Hooks.AFTER_SWAP_FLAG
//        );
//
//        // Deploy hook to the correct address using proper method
//        bytes memory constructorArgs = abi.encode(poolManager);
//        address hookAddress =
//            deployHookToProperAddress("YieldMaximizerHook.sol:YieldMaximizerHook", constructorArgs, flags);
//        hook = YieldMaximizerHook(hookAddress);
//
//        // Create the pool
//        (poolKey, poolId) = createPool(currency0, currency1, IHooks(address(hook)), FEE, TICK_SPACING, SQRT_PRICE_1_1);
//
//        // Fund test accounts
//        _fundTestAccounts();
//
//        console.log("=== Setup Complete ===");
//        console.log("PoolManager:", address(poolManager));
//        console.log("Hook:", address(hook));
//        console.log("Currency0:", Currency.unwrap(currency0));
//        console.log("Currency1:", Currency.unwrap(currency1));
//        console.log("PoolId:", uint256(PoolId.unwrap(poolId)));
//    }
//
//    function _fundTestAccounts() internal {
//        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
//        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
//
//        // Mint tokens to test accounts
//        token0.mint(alice, 1000 ether);
//        token1.mint(alice, 1000 ether);
//        token0.mint(bob, 1000 ether);
//        token1.mint(bob, 1000 ether);
//        token0.mint(charlie, 1000 ether);
//        token1.mint(charlie, 1000 ether);
//
//        console.log("Funded test accounts with tokens");
//    }
//
//    function testActivateStrategy() public {
//        console.log("\n=== Testing Strategy Activation ===");
//
//        // Alice activates strategy with valid parameters
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Check strategy was activated correctly
//        (
//            bool isActive,
//            uint256 totalDeposited,
//            uint256 totalCompounded,
//            uint256 lastCompoundTime,
//            uint256 gasThreshold,
//            uint8 riskLevel
//        ) = hook.userStrategies(alice);
//
//        assertTrue(isActive, "Strategy should be active");
//        assertEq(totalDeposited, 0, "Initial deposited should be 0");
//        assertEq(totalCompounded, 0, "Initial compounded should be 0");
//        assertEq(gasThreshold, 50 gwei, "Gas threshold should match");
//        assertEq(riskLevel, 5, "Risk level should match");
//        assertEq(lastCompoundTime, block.timestamp, "Last compound time should be current");
//
//        // Check pool stats updated
//        (uint256 totalUsers,,, bool poolActive) = hook.poolStrategies(poolId);
//        assertEq(totalUsers, 0, "Pool should have 0 user"); // the user is added after swap was done.
//        assertTrue(poolActive, "Pool should be active");
//
//        console.log("Strategy activation successful");
//    }
//
//    function testDeactivateStrategy() public {
//        console.log("\n=== Testing Strategy Deactivation ===");
//
//        // First activate
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Then deactivate
//        vm.prank(alice);
//        hook.deactivateStrategy(poolId);
//
//        // Check strategy was deactivated
//        (bool isActive,,,,,) = hook.userStrategies(alice);
//        assertFalse(isActive, "Strategy should be inactive");
//
//        // Check pool stats updated
//        (uint256 totalUsers,,,) = hook.poolStrategies(poolId);
//        assertEq(totalUsers, 0, "Pool should have 0 users");
//
//        console.log("Strategy deactivation successful");
//    }
//
//    function testUpdateStrategy() public {
//        console.log("\n=== Testing Strategy Updates ===");
//
//        // Activate first
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Update parameters
//        vm.prank(alice);
//        hook.updateStrategy(75 gwei, 8);
//
//        // Check parameters were updated
//        (,,,, uint256 gasThreshold, uint8 riskLevel) = hook.userStrategies(alice);
//        assertEq(gasThreshold, 75 gwei, "Gas threshold should be updated");
//        assertEq(riskLevel, 8, "Risk level should be updated");
//
//        console.log("Strategy update successful");
//    }
//
//    function testRejectInvalidParameters() public {
//        console.log("\n=== Testing Invalid Parameter Rejection ===");
//
//        // Test invalid risk levels
//        vm.prank(alice);
//        vm.expectRevert("Invalid risk level");
//        hook.activateStrategy(poolId, 50 gwei, 0); // Too low
//
//        vm.prank(alice);
//        vm.expectRevert("Invalid risk level");
//        hook.activateStrategy(poolId, 50 gwei, 11); // Too high
//
//        // Test invalid gas thresholds
//        vm.prank(alice);
//        vm.expectRevert("Invalid gas threshold");
//        hook.activateStrategy(poolId, 0, 5); // Zero gas
//
//        vm.prank(alice);
//        vm.expectRevert("Invalid gas threshold");
//        hook.activateStrategy(poolId, 200 gwei, 5); // Too high
//
//        // Valid parameters should work
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        (bool isActive,,,,,) = hook.userStrategies(alice);
//        assertTrue(isActive, "Valid parameters should work");
//
//        console.log("Invalid parameter rejection working correctly");
//    }
//
//    function testCannotActivateTwice() public {
//        console.log("\n=== Testing Double Activation Prevention ===");
//
//        // Activate once
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Try to activate again - should fail
//        vm.prank(alice);
//        vm.expectRevert("Strategy already active");
//        hook.activateStrategy(poolId, 60 gwei, 6);
//
//        console.log("Double activation prevention working");
//    }
//
//    function testCannotDeactivateInactiveStrategy() public {
//        console.log("\n=== Testing Inactive Strategy Protection ===");
//
//        // Try to deactivate without activating first
//        vm.prank(alice);
//        vm.expectRevert("User strategy not active");
//        hook.deactivateStrategy(poolId);
//
//        console.log("Inactive strategy protection working");
//    }
//
//    function testCannotUpdateInactiveStrategy() public {
//        console.log("\n=== Testing Update Protection ===");
//
//        // Try to update without activating first
//        vm.prank(alice);
//        vm.expectRevert("User strategy not active");
//        hook.updateStrategy(60 gwei, 6);
//
//        console.log("Update protection working");
//    }
//
//    function testMultipleUsersCanActivate() public {
//        console.log("\n=== Testing Multiple User Support ===");
//
//        // Alice activates
//        vm.prank(alice);
//        hook.activateStrategy(poolId, 50 gwei, 5);
//
//        // Bob activates with different parameters
//        vm.prank(bob);
//        hook.activateStrategy(poolId, 75 gwei, 7);
//
//        // Charlie activates
//        vm.prank(charlie);
//        hook.activateStrategy(poolId, 60 gwei, 3);
//
//        // Check all are active
//        (bool aliceActive,,,,,) = hook.userStrategies(alice);
//        (bool bobActive,,,,,) = hook.userStrategies(bob);
//        (bool charlieActive,,,,,) = hook.userStrategies(charlie);
//
//        assertTrue(aliceActive, "Alice should be active");
//        assertTrue(bobActive, "Bob should be active");
//        assertTrue(charlieActive, "Charlie should be active");
//
//        // Check pool has 0 users
//        // the user is added after swap was done.
//        (uint256 totalUsers,,,) = hook.poolStrategies(poolId);
//        assertEq(totalUsers, 0, "Pool should have 0 users");
//
//        console.log("Multiple user support working");
//    }
//}
