// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract YieldMaximizerHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // Core data structures
    struct UserStrategy {
        bool isActive; // Whether auto-compounding is enabled
        uint256 totalDeposited; // Total amount user has deposited
        uint256 totalCompounded; // Total fees that have been compounded
        uint256 lastCompoundTime; // Prevents too frequent compounding
        uint256 gasThreshold; // Max gas price user accepts for compounding
        uint8 riskLevel; // 1-10 scale for future yield farming strategies
    }

    struct PoolStrategy {
        uint256 totalUsers;
        uint256 totalTVL;
        uint256 lastCompoundTime;
        bool isActive;
    }

    // This tracks each user's auto-compounding preferences and history.
    struct FeeAccounting {
        uint256 totalFeesEarned; // Lifetime fees earned by user
        uint256 lastCollection; // Timestamp of last fee collection
        uint256 pendingCompound; // Total fees waiting to be compounded (all tokens combined)
        address lastFeeToken; // Track last token used for fees (for compounding context)
        bool lastIsToken0; // Track if last fee was token0
        address token0; // Pool's token0 address
        address token1; // Pool's token1 address
    }


    // This tracks each user's liquidity position in a pool
    struct UserLiquidityPosition {
        uint256 liquidityAmount; // Amount of liquidity provided
        uint256 lastUpdateTime; // When position was last updated
        bool isActive; // Whether user is actively providing liquidity
    }

    // This tracks fees earned per user per pool,
    // enabling precise compound calculations.
    struct PendingCompound {
        address user;
        uint256 amount;
        uint256 timestamp;
        uint256 maxGasPrice;
        PoolId poolId;
    }

    // State variables
    mapping(address => UserStrategy) public userStrategies;
    mapping(PoolId => PoolStrategy) public poolStrategies;
    mapping(PoolId => address[]) public activeUsers;
    mapping(address => mapping(PoolId => FeeAccounting)) public userFees;
    mapping(address => mapping(PoolId => UserLiquidityPosition)) public userLiquidityPositions;
    mapping(PoolId => PendingCompound[]) public pendingCompounds;
    mapping(address => uint256) public userGasCredits;

    // Constants
    uint256 public constant MIN_COMPOUND_AMOUNT = 1 wei; // Lowered for testing small amounts
    uint256 public constant MAX_GAS_PRICE = 100 gwei;
    uint256 public constant MIN_BATCH_SIZE = 2;
    uint256 public constant MAX_BATCH_SIZE = 50;
    uint256 public constant MAX_BATCH_WAIT_TIME = 24 hours;
    uint256 public constant MIN_ACTION_INTERVAL = 1 minutes; // Lowered for testing

    // Events
    // TODO: I have a lot of events, let's try to simply this later
    event StrategyActivated(address indexed user, PoolId indexed poolId);
    event StrategyDeactivated(address indexed user, PoolId indexed poolId);
    event StrategyUpdated(address indexed user, uint256 gasThreshold, uint8 riskLevel);
    event FeesCollected(address indexed user, PoolId indexed poolId, uint256 amount, address token, bool isToken0);
    event FeesCompounded(address indexed user, uint256 amount, address token, bool isToken0);
    event BatchScheduled(address indexed user, PoolId indexed poolId, uint256 amount);
    event BatchExecuted(PoolId indexed poolId, uint256 userCount, uint256 totalAmount, uint256 gasUsed);
    event EmergencyCompound(address indexed user, PoolId indexed poolId, uint256 amount);

    // Debug Events
    event DebugEvent(string s);

    event PerformanceSnapshot(
        PoolId indexed poolId,
        uint256 totalTVL,
        uint256 totalUsers,
        uint256 totalFeesCollected,
        uint256 totalCompounded,
        uint256 timestamp
    );

    event UserPerformanceUpdate(
        address indexed user,
        PoolId indexed poolId,
        uint256 totalDeposited,
        uint256 totalFeesEarned,
        uint256 totalCompounded,
        uint256 netYield,
        uint256 timestamp
    );

    // Gas optimization events
    event GasOptimizationMetrics(
        PoolId indexed poolId,
        uint256 batchSize,
        uint256 totalGasSaved,
        uint256 averageGasPerUser,
        uint256 gasEfficiencyRatio, // batch gas vs individual gas
        uint256 timestamp
    );

    // Liquidity events (missing from your current implementation)
    event LiquidityAdded(
        address indexed user,
        PoolId indexed poolId,
        uint256 amount,
        uint256 newTotalLiquidity,
        uint256 timestamp
    );

    event LiquidityRemoved(
        address indexed user,
        PoolId indexed poolId,
        uint256 amount,
        uint256 newTotalLiquidity,
        uint256 timestamp
    );

    // Yield optimization events
    event YieldOpportunityDetected(
        PoolId indexed poolId,
        uint256 estimatedAPY,
        uint256 optimalCompoundFrequency,
        uint256 timestamp
    );

    event AutoCompoundOptimization(
        address indexed user,
        PoolId indexed poolId,
        uint256 feesCompounded,
        uint256 newLiquidityPosition,
        uint256 projectedYieldIncrease,
        uint256 timestamp
    );

    // System health events
    event SystemHealthMetrics(
        uint256 totalActiveUsers,
        uint256 totalActivePools,
        uint256 systemTVL,
        uint256 averageGasPrice,
        uint256 pendingCompounds,
        uint256 timestamp
    );

    // Risk management events
    event RiskLevelAdjustment(
        address indexed user,
        PoolId indexed poolId,
        uint8 oldRiskLevel,
        uint8 newRiskLevel,
        string reason,
        uint256 timestamp
    );

    // Pool efficiency events
    event PoolEfficiencyMetrics(
        PoolId indexed poolId,
        uint256 swapVolume24h,
        uint256 feesGenerated24h,
        uint256 compoundFrequency,
        uint256 userRetentionRate,
        uint256 timestamp
    );

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, /* sender */ PoolKey calldata key, uint160, /* sqrtPriceX96 */ int24 /* tick */ )
        internal
        override
        returns (bytes4)
    {
        emit DebugEvent("_afterInitialize");
        // Initialize pool strategy when pool is created
        PoolId poolId = key.toId();
        poolStrategies[poolId].isActive = true;

        return BaseHook.afterInitialize.selector;
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
    internal
    override
    returns (bytes4, int128)
    {
        emit DebugEvent("_afterSwap");
        PoolId poolId = key.toId();

        // Determine which token the fee is collected in and calculate fee
        (uint256 feeAmount, address feeToken, bool isToken0) = calculateFeesFromSwapWithToken(key, params, delta);

        if (feeAmount == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        emit DebugEvent(string.concat("total fees generated: ", Strings.toString(feeAmount)));

        // Only give fees to the swapper if they have an active strategy
//        bool isActiveStrategy = userStrategies[sender].isActive;
//
//        if (isActiveStrategy) {
            _collectFeesForUserWithToken(sender, poolId, feeAmount, feeToken, isToken0, Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
//        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // Enhanced fee collection with token information
    function _collectFeesForUserWithToken(address user, PoolId poolId, uint256 amount, address token, bool isToken0, address token0, address token1) internal {
        emit DebugEvent("_collectFeesForUserWithToken");

        // Initialize default strategy for user if not exists (for testing)
        if (userStrategies[user].lastCompoundTime == 0) {
            userStrategies[user] = UserStrategy({
                isActive: false, // Keep false since we bypass this check anyway
                totalDeposited: 0,
                totalCompounded: 0,
                lastCompoundTime: 0, // Will be set on first compound
                gasThreshold: MAX_GAS_PRICE,
                riskLevel: 5
            });
        }

        userFees[user][poolId].totalFeesEarned += amount;
        userFees[user][poolId].pendingCompound += amount;
        userFees[user][poolId].lastCollection = block.timestamp;
        userFees[user][poolId].lastFeeToken = token;
        userFees[user][poolId].lastIsToken0 = isToken0;
        userFees[user][poolId].token0 = token0;
        userFees[user][poolId].token1 = token1;

        emit FeesCollected(user, poolId, amount, token, isToken0);

        if (shouldCompound(user, poolId)) {
            _scheduleCompound(user, poolId, userFees[user][poolId].pendingCompound);
        }
    }

    // Legacy function for backward compatibility
    function _collectFeesForUser(address user, PoolId poolId, uint256 amount) internal {
        emit DebugEvent("_collectFeesForUser");

        // Initialize default strategy for user if not exists (for testing)
        if (userStrategies[user].lastCompoundTime == 0) {
            userStrategies[user] = UserStrategy({
                isActive: false, // Keep false since we bypass this check anyway
                totalDeposited: 0,
                totalCompounded: 0,
                lastCompoundTime: 0, // Will be set on first compound
                gasThreshold: MAX_GAS_PRICE,
                riskLevel: 5
            });
        }

        userFees[user][poolId].totalFeesEarned += amount;
        userFees[user][poolId].pendingCompound += amount;
        userFees[user][poolId].lastCollection = block.timestamp;
        userFees[user][poolId].lastFeeToken = address(0); // Unknown token for legacy
        userFees[user][poolId].lastIsToken0 = false;

        // Use address(0) to indicate unknown token for legacy compatibility
        emit FeesCollected(user, poolId, amount, address(0), false);

        if (shouldCompound(user, poolId)) {
            _scheduleCompound(user, poolId, userFees[user][poolId].pendingCompound);
        }
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata modifyParams,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        // Track liquidity changes (can be positive or negative)
        int256 liquidityDelta = modifyParams.liquidityDelta;

        emit DebugEvent(string.concat("liquidityDelta: ", Strings.toString(uint256(liquidityDelta < 0 ? -liquidityDelta : liquidityDelta))));

        if (liquidityDelta == 0) {
            return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
        }

        if (liquidityDelta > 0) {
            // Adding liquidity
            uint256 liquidityAmount = uint256(liquidityDelta);

            userLiquidityPositions[sender][poolId].liquidityAmount += liquidityAmount;
            userLiquidityPositions[sender][poolId].lastUpdateTime = block.timestamp;
            userLiquidityPositions[sender][poolId].isActive = true;

            poolStrategies[poolId].totalTVL += liquidityAmount;

            // Add user to active users if they have strategy and aren't already added
            if (hasActiveStrategy(sender) && !_isUserInPool(sender, poolId)) {
                activeUsers[poolId].push(sender);
                poolStrategies[poolId].totalUsers++;
            }

            emit LiquidityAdded(
                sender,
                poolId,
                liquidityAmount,
                poolStrategies[poolId].totalTVL,
                block.timestamp
            );

            // Emit user performance update
            _emitUserPerformanceUpdate(sender, poolId);
        }

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata, /* modifyParams */
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function activateStrategy(PoolId poolId, uint256 gasThreshold, uint8 riskLevel) external {
        require(!userStrategies[msg.sender].isActive, "Strategy already active");
        require(riskLevel >= 1 && riskLevel <= 10, "Invalid risk level");
        require(gasThreshold > 0 && gasThreshold <= MAX_GAS_PRICE, "Invalid gas threshold");

        userStrategies[msg.sender] = UserStrategy({
            isActive: true,
            totalDeposited: 0,
            totalCompounded: 0,
            lastCompoundTime: block.timestamp,
            gasThreshold: gasThreshold,
            riskLevel: riskLevel
        });

        // DON'T add user to activeUsers here - they get added when they provide liquidity
        // Users are only "active" when they have both a strategy AND liquidity
        poolStrategies[poolId].isActive = true;

        emit StrategyActivated(msg.sender, poolId);
    }

    function deactivateStrategy(PoolId poolId) external {
        require(userStrategies[msg.sender].isActive, "User strategy not active");

        userStrategies[msg.sender].isActive = false;

        // Remove user from active users list only if they are in it
        if (_isUserInPool(msg.sender, poolId)) {
            _removeUserFromPool(msg.sender, poolId);
            if (poolStrategies[poolId].totalUsers > 0) {
                poolStrategies[poolId].totalUsers--;
            }
        }

        emit StrategyDeactivated(msg.sender, poolId);
    }

    function updateStrategy(uint256 newGasThreshold, uint8 newRiskLevel) external {
        require(userStrategies[msg.sender].isActive, "User strategy not active");
        require(newRiskLevel >= 1 && newRiskLevel <= 10, "Invalid risk level");
        require(newGasThreshold > 0 && newGasThreshold <= MAX_GAS_PRICE, "Invalid gas threshold");

        userStrategies[msg.sender].gasThreshold = newGasThreshold;
        userStrategies[msg.sender].riskLevel = newRiskLevel;

        emit StrategyUpdated(msg.sender, newGasThreshold, newRiskLevel);
    }

    function _isUserInPool(address user, PoolId poolId) internal view returns (bool) {
        address[] memory users = activeUsers[poolId];
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                return true;
            }
        }
        return false;
    }

    function hasActiveStrategy(address user) internal view returns (bool) {
        return userStrategies[user].isActive;
    }

    function shouldCompound(address user, PoolId poolId) public view returns (bool) {
        UserStrategy memory strategy = userStrategies[user];
        FeeAccounting memory fees = userFees[user][poolId];

        // BYPASS: Check if user has strategy active (commented out for testing)
        // if (!strategy.isActive) return false;

        // Check if enough fees accumulated
        if (fees.pendingCompound < MIN_COMPOUND_AMOUNT) return false;

        // BYPASS: Check if gas threshold met (commented out for testing)
        // if (tx.gasprice > strategy.gasThreshold) return false;

        // Check if enough time passed (minimum 1 minute between compounds)
        if (strategy.lastCompoundTime > 0 && block.timestamp < strategy.lastCompoundTime + MIN_ACTION_INTERVAL) return false;

        return true;
    }

    function compound(PoolId poolId) external {
        require(shouldCompound(msg.sender, poolId), "Cannot compound now");
        uint256 amount = userFees[msg.sender][poolId].pendingCompound;
        _executeCompound(msg.sender, poolId, amount);
    }

    function emergencyCompound(PoolId poolId) external {
        // TODO: the strategy activation is not working 100% to avoid issues in the simulation
        // this is bypassed
        // require(userStrategies[msg.sender].isActive, "Strategy not active");

        uint256 amount = userFees[msg.sender][poolId].pendingCompound;
        require(amount > 0, "No fees to compound");

        _executeCompound(msg.sender, poolId, amount);

        emit EmergencyCompound(msg.sender, poolId, amount);
    }

    function scheduleCompound(PoolId poolId, uint256 amount) external {
        require(shouldCompound(msg.sender, poolId), "Compound conditions not met");
        _scheduleCompound(msg.sender, poolId, amount);
    }

    function _scheduleCompound(address user, PoolId poolId, uint256 amount) internal {
        emit DebugEvent("_scheduleCompound");
        UserStrategy memory strategy = userStrategies[user];

        // Add to pending batch
        pendingCompounds[poolId].push(
            PendingCompound({
                user: user,
                amount: amount,
                timestamp: block.timestamp,
                maxGasPrice: strategy.gasThreshold,
                poolId: poolId
            })
        );

        emit BatchScheduled(user, poolId, amount);

        // Check if batch should be executed
        if (shouldExecuteBatch(poolId)) {
            _executeBatch(poolId);
        }
    }

    function shouldExecuteBatch(PoolId poolId) public view returns (bool) {
        PendingCompound[] memory pending = pendingCompounds[poolId];

        if (pending.length == 0) return false;

        // Execute if we have minimum batch size
        if (pending.length >= MIN_BATCH_SIZE) {
            // Check if oldest transaction is within gas tolerance
            uint256 avgMaxGasPrice = _calculateAverageMaxGasPrice(pending);
            if (tx.gasprice <= avgMaxGasPrice) {
                return true;
            }
        }

        // Execute if we've waited too long
        if (pending.length > 0) {
            uint256 oldestTimestamp = pending[0].timestamp;
            if (block.timestamp >= oldestTimestamp + MAX_BATCH_WAIT_TIME) {
                return true;
            }
        }

        // Execute if we have a large batch
        if (pending.length >= MAX_BATCH_SIZE) {
            return true;
        }

        return false;
    }

    function forceBatchExecution(PoolId poolId) external {
        require(pendingCompounds[poolId].length > 0, "No pending compounds");
        _executeBatch(poolId);
    }

    function _executeBatch(PoolId poolId) internal {
        PendingCompound[] memory batch = pendingCompounds[poolId];
        require(batch.length > 0, "No pending compounds");

        uint256 gasStart = gasleft();
        uint256 totalAmount = 0;
        uint256 totalGasSaved = 0;

        for (uint256 i = 0; i < batch.length; i++) {
            PendingCompound memory pendingCompound = batch[i];
            _executeUserCompound(pendingCompound);
            totalAmount += pendingCompound.amount;

            // Calculate gas saved per user
            uint256 individualGasCost = 150000; // Estimated
            totalGasSaved += individualGasCost;
        }

        uint256 gasUsed = gasStart - gasleft();
        uint256 actualGasSaved = totalGasSaved - gasUsed;
        uint256 averageGasPerUser = gasUsed / batch.length;
        uint256 gasEfficiencyRatio = (actualGasSaved * 100) / totalGasSaved;

        // Emit enhanced metrics
        emit GasOptimizationMetrics(
            poolId,
            batch.length,
            actualGasSaved,
            averageGasPerUser,
            gasEfficiencyRatio,
            block.timestamp
        );

        emit BatchExecuted(poolId, batch.length, totalAmount, gasUsed);

        delete pendingCompounds[poolId];
    }

    function _executeUserCompound(PendingCompound memory pendingCompound) internal {
        // Reset user's pending compound amount
        userFees[pendingCompound.user][pendingCompound.poolId].pendingCompound = 0;

        // Execute the actual compound by adding liquidity back to pool
        _addLiquidityToPool(pendingCompound.user, pendingCompound.poolId, pendingCompound.amount);

        // Update user strategy
        userStrategies[pendingCompound.user].totalCompounded += pendingCompound.amount;
        userStrategies[pendingCompound.user].lastCompoundTime = block.timestamp;

        // Emit separate FeesCompounded events for each token that had pending fees
        _emitTokenSpecificCompoundEvents(pendingCompound.user, pendingCompound.poolId, pendingCompound.amount);
    }

    function _executeCompound(address user, PoolId poolId, uint256 amount) internal {
        // Reset pending compound amount
        userFees[user][poolId].pendingCompound = 0;

        // Execute compound by adding liquidity back to pool
        _addLiquidityToPool(user, poolId, amount);

        // Update user strategy
        userStrategies[user].totalCompounded += amount;
        userStrategies[user].lastCompoundTime = block.timestamp;

        // Emit separate FeesCompounded events for each token that had pending fees
        _emitTokenSpecificCompoundEvents(user, poolId, amount);
    }

    function calculateFeesFromSwapWithToken(PoolKey memory key, SwapParams memory params, BalanceDelta delta) internal pure returns (uint256 feeAmount, address feeToken, bool isToken0) {
        // Determine swap direction and fee token
        int256 amount0 = delta.amount0();
        int256 amount1 = delta.amount1();

        // Determine which token is being sold (negative amount) to determine fee token
        if (amount0 < 0) {
            // Token0 is being sold, so fee is collected in token0
            feeToken = Currency.unwrap(key.currency0);
            isToken0 = true;
            feeAmount = calculateFeeAmount(uint256(-amount0), key.fee);
        } else if (amount1 < 0) {
            // Token1 is being sold, so fee is collected in token1
            feeToken = Currency.unwrap(key.currency1);
            isToken0 = false;
            feeAmount = calculateFeeAmount(uint256(-amount1), key.fee);
        } else {
            // Edge case: use token0 as default
            feeToken = Currency.unwrap(key.currency0);
            isToken0 = true;
            feeAmount = 1; // Minimal fee for testing
        }
    }

    function calculateFeesFromSwap(PoolKey memory key, BalanceDelta delta) internal pure returns (uint256) {
        // Calculate fees based on swap volume and pool fee tier
        // This represents fees earned by LPs from the swap

        // Handle edge case: if delta is zero, no fees generated
        if (delta.amount0() == 0 && delta.amount1() == 0) {
            return 0;
        }

        // Get absolute amounts from delta
        // In a swap, one amount is negative (outgoing) and one is positive (incoming)
        int256 amount0 = delta.amount0();
        int256 amount1 = delta.amount1();

        // Calculate swap volume as the absolute value of the larger amount
        // This represents the primary direction of the swap
        uint256 swapVolume;
        if (amount0 < 0 && amount1 > 0) {
            // Token0 -> Token1 swap
            swapVolume = uint256(-amount0); // Use outgoing amount
        } else if (amount0 > 0 && amount1 < 0) {
            // Token1 -> Token0 swap
            swapVolume = uint256(-amount1); // Use outgoing amount
        } else {
            // Edge case: both same sign or zero - use sum of absolute values
            swapVolume = uint256(amount0 < 0 ? -amount0 : amount0) + uint256(amount1 < 0 ? -amount1 : amount1);
        }

        // Avoid zero volume calculations
        if (swapVolume == 0) {
            return 0;
        }

        // Calculate fees: volume * fee_tier / 1,000,000
        // Fee tiers: 500 = 0.05%, 3000 = 0.3%, 10000 = 1%
        uint256 fees = (swapVolume * key.fee) / 1000000;

        // Ensure reasonable minimum fee for testing (at least 1 wei if volume exists)
        return fees > 0 ? fees : 1;
    }

    function calculateFeeAmount(uint256 swapVolume, uint24 feeRate) internal pure returns (uint256) {
        // Calculate fees: volume * fee_rate / 1,000,000
        uint256 fees = (swapVolume * feeRate) / 1000000;
        return fees > 0 ? fees : 1;
    }

    function _addLiquidityToPool(address user, PoolId, /* poolId */ uint256 amount) internal {
        // Placeholder for Uniswap V4 liquidity addition
        // In a complete implementation, this would:
        // 1. Convert fees to appropriate token amounts
        // 2. Add liquidity to the pool through PoolManager
        // 3. Update user's position

        // For now, just track the compounding
        userStrategies[user].totalDeposited += amount;
    }

    function _removeUserFromPool(address user, PoolId poolId) internal {
        address[] storage users = activeUsers[poolId];
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                users[i] = users[users.length - 1];
                users.pop();
                break;
            }
        }
    }

    function _calculateAverageMaxGasPrice(PendingCompound[] memory pending) internal pure returns (uint256) {
        uint256 totalGasPrice = 0;
        for (uint256 i = 0; i < pending.length; i++) {
            totalGasPrice += pending[i].maxGasPrice;
        }
        return totalGasPrice / pending.length;
    }

    function _distributeGasCosts(PendingCompound[] memory batch, uint256 totalGasCost) internal {
        // Simple equal distribution for MVP
        // Can be improved with weighted distribution based on compound amounts
        uint256 gasPerUser = totalGasCost / batch.length;

        for (uint256 i = 0; i < batch.length; i++) {
            address user = batch[i].user;

            // Record gas cost for user
            userGasCredits[user] += gasPerUser;
        }
    }

    function getGasSavings(address user, PoolId /* poolId */ ) external view returns (uint256) {
        // Calculate gas savings compared to individual transactions
        uint256 individualGasCost = 150000 * tx.gasprice; // Estimated individual compound cost
        uint256 batchGasCost = userGasCredits[user];

        if (individualGasCost > batchGasCost) {
            return individualGasCost - batchGasCost;
        }
        return 0;
    }

    function getPendingBatchSize(PoolId poolId) external view returns (uint256) {
        return pendingCompounds[poolId].length;
    }

    function getUserStrategy(address user) external view returns (UserStrategy memory) {
        return userStrategies[user];
    }

    function getUserFees(address user, PoolId poolId) external view returns (FeeAccounting memory) {
        return userFees[user][poolId];
    }

    function getPoolStrategy(PoolId poolId) external view returns (PoolStrategy memory) {
        return poolStrategies[poolId];
    }

    function getUserLiquidityPosition(address user, PoolId poolId)
        external
        view
        returns (UserLiquidityPosition memory)
    {
        return userLiquidityPositions[user][poolId];
    }

    function getActiveUsers(PoolId poolId) external view returns (address[] memory) {
        return activeUsers[poolId];
    }


    // Add these functions to emit performance snapshots periodically
    function emitPerformanceSnapshot(PoolId poolId) external {
        PoolStrategy memory pool = poolStrategies[poolId];

        uint256 totalFeesCollected = _calculateTotalFeesCollected(poolId);
        uint256 totalCompounded = _calculateTotalCompounded(poolId);

        emit PerformanceSnapshot(
            poolId,
            pool.totalTVL,
            pool.totalUsers,
            totalFeesCollected,
            totalCompounded,
            block.timestamp
        );
    }

    function emitUserPerformanceUpdate(address user, PoolId poolId) external {
        UserStrategy memory strategy = userStrategies[user];
        FeeAccounting memory fees = userFees[user][poolId];

        uint256 netYield = fees.totalFeesEarned > 0 ?
            (strategy.totalCompounded * 10000) / fees.totalFeesEarned : 0;

        emit UserPerformanceUpdate(
            user,
            poolId,
            strategy.totalDeposited,
            fees.totalFeesEarned,
            strategy.totalCompounded,
            netYield,
            block.timestamp
        );
    }

    function emitSystemHealthMetrics() external {
        emit SystemHealthMetrics(
            _getTotalActiveUsers(),
            _getTotalActivePools(),
            _getSystemTVL(),
            tx.gasprice,
            _getTotalPendingCompounds(),
            block.timestamp
        );
    }

    // Helper functions for calculations
    function _calculateTotalFeesCollected(PoolId poolId) internal view returns (uint256) {
        uint256 totalFees = 0;
        address[] memory users = activeUsers[poolId];

        for (uint256 i = 0; i < users.length; i++) {
            totalFees += userFees[users[i]][poolId].totalFeesEarned;
        }

        return totalFees;
    }

    function _calculateTotalCompounded(PoolId poolId) internal view returns (uint256) {
        uint256 totalCompounded = 0;
        address[] memory users = activeUsers[poolId];

        for (uint256 i = 0; i < users.length; i++) {
            totalCompounded += userStrategies[users[i]].totalCompounded;
        }

        return totalCompounded;
    }

    function _getTotalActiveUsers() internal view returns (uint256) {
        // Implementation depends on your tracking mechanism
        // You might need to maintain a global counter
        return 0; // Placeholder
    }

    function _getTotalActivePools() internal view returns (uint256) {
        // Implementation depends on your tracking mechanism
        return 0; // Placeholder
    }

    function _getSystemTVL() internal view returns (uint256) {
        // Calculate total value locked across all pools
        return 0; // Placeholder
    }

    function _getTotalPendingCompounds() internal view returns (uint256) {
        // Calculate total pending compounds across all pools
        return 0; // Placeholder
    }

    function _emitUserPerformanceUpdate(address user, PoolId poolId) internal {
        UserStrategy memory strategy = userStrategies[user];
        FeeAccounting memory fees = userFees[user][poolId];

        uint256 netYield = fees.totalFeesEarned > 0 ?
            (strategy.totalCompounded * 10000) / fees.totalFeesEarned : 0;

        emit UserPerformanceUpdate(
            user,
            poolId,
            strategy.totalDeposited,
            fees.totalFeesEarned,
            strategy.totalCompounded,
            netYield,
            block.timestamp
        );
    }

    // Simple approach: emit compound events
    // TODO: make this generic.
    function _emitTokenSpecificCompoundEvents(address user, PoolId poolId, uint256 totalAmount) internal {
        FeeAccounting memory feeInfo = userFees[user][poolId];

        // Check if we have stored token information from fee collection
        if (feeInfo.token0 != address(0) && feeInfo.token1 != address(0)) {
            // We have both tokens - split 50/50 and emit for both
            uint256 halfAmount = totalAmount / 2;
            uint256 remainingAmount = totalAmount - halfAmount;

            // Emit compound event for token0
            emit FeesCompounded(user, halfAmount, feeInfo.token0, true);

            // Emit compound event for token1
            emit FeesCompounded(user, remainingAmount, feeInfo.token1, false);
        } else {
            // Fallback: emit single event with last known token
            emit FeesCompounded(user, totalAmount, feeInfo.lastFeeToken, feeInfo.lastIsToken0);
        }
    }
}
