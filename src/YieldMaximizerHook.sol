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
        uint256 pendingCompound; // Fees waiting to be compounded
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

    struct BatchExecution {
        PoolId poolId;
        uint256 totalAmount;
        uint256 userCount;
        uint256 gasUsed;
        uint256 timestamp;
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
    uint256 public constant MIN_COMPOUND_AMOUNT = 0.001 ether;
    uint256 public constant MAX_GAS_PRICE = 100 gwei;
    uint256 public constant MIN_BATCH_SIZE = 2;
    uint256 public constant MAX_BATCH_SIZE = 50;
    uint256 public constant MAX_BATCH_WAIT_TIME = 24 hours;
    uint256 public constant MIN_ACTION_INTERVAL = 1 hours;

    // Events
    event StrategyActivated(address indexed user, PoolId indexed poolId);
    event StrategyDeactivated(address indexed user, PoolId indexed poolId);
    event StrategyUpdated(address indexed user, uint256 gasThreshold, uint8 riskLevel);
    event FeesCollected(address indexed user, PoolId indexed poolId, uint256 amount);
    event FeesCompounded(address indexed user, uint256 amount);
    event BatchScheduled(address indexed user, PoolId indexed poolId, uint256 amount);
    event BatchExecuted(PoolId indexed poolId, uint256 userCount, uint256 totalAmount, uint256 gasUsed);
    event EmergencyCompound(address indexed user, PoolId indexed poolId, uint256 amount);
    event UserAddedToPool(address indexed user, PoolId indexed poolId, uint256 liquidityAmount);
    event UserRemovedFromPool(address indexed user, PoolId indexed poolId);

    // Debug Events
    event DebugSwapEntered(address indexed sender, PoolId indexed poolId, uint256 blockNumber);
    event DebugSwapCalculation(
        PoolId indexed poolId, uint256 totalFeesGenerated, uint256 totalPoolLiquidity, uint256 activeUsersCount
    );
    event DebugUserFeeShare(
        address indexed user, PoolId indexed poolId, uint256 userLiquidity, uint256 userFeeShare, bool hasActiveStrategy
    );
    event DebugSwapError(string reason, PoolId indexed poolId, address indexed sender);
    event DebugActiveUsers(PoolId indexed poolId, uint256 count);

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
        // Initialize pool strategy when pool is created
        PoolId poolId = key.toId();
        poolStrategies[poolId].isActive = true;

        return BaseHook.afterInitialize.selector;
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        uint256 totalFeesGenerated = calculateFeesFromSwap(key, delta);

        // Guard clause: Exit early if no fees were generated.
        if (totalFeesGenerated == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 totalPoolLiquidity = getTotalPoolLiquidity(poolId);

        // Case 1: Active LPs exist in the pool.
        if (totalPoolLiquidity > 0) {
            address[] memory users = activeUsers[poolId];
            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i];

                // Guard clause: Skip users without an active strategy or position.
                if (!userStrategies[user].isActive || !userLiquidityPositions[user][poolId].isActive) {
                    continue;
                }

                uint256 userLiquidity = userLiquidityPositions[user][poolId].liquidityAmount;
                uint256 userFeeShare = (totalFeesGenerated * userLiquidity) / totalPoolLiquidity;

                if (userFeeShare > 0) {
                    _collectFeesForUser(user, poolId, userFeeShare);
                }
            }
            return (BaseHook.afterSwap.selector, 0);
        }

        // Case 2: No active LPs, but the swapper has an active strategy.
        if (userStrategies[sender].isActive) {
            _collectFeesForUser(sender, poolId, totalFeesGenerated);
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // Private helper function to consolidate fee collection logic.
    function _collectFeesForUser(address user, PoolId poolId, uint256 amount) internal {
        userFees[user][poolId].totalFeesEarned += amount;
        userFees[user][poolId].pendingCompound += amount;
        userFees[user][poolId].lastCollection = block.timestamp;

        emit FeesCollected(user, poolId, amount);

        if (shouldCompound(user, poolId)) {
            _scheduleCompound(user, poolId, userFees[user][poolId].pendingCompound);
        }
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata modifyParams,
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        // Determine the actual user - either from hookData or sender
        address actualUser = sender;
        if (hookData.length > 0) {
            // Decode user address from hookData if provided
            actualUser = abi.decode(hookData, (address));
        }

        // Calculate liquidity amount from delta (use absolute values)
        uint256 liquidityAdded = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0()))
            + uint256(int256(delta.amount1() > 0 ? delta.amount1() : -delta.amount1()));

        // Update user's liquidity position
        if (liquidityAdded > 0) {
            userLiquidityPositions[actualUser][poolId].liquidityAmount += liquidityAdded;
            userLiquidityPositions[actualUser][poolId].lastUpdateTime = block.timestamp;
            userLiquidityPositions[actualUser][poolId].isActive = true;

            // CRITICAL FIX: Add user to activeUsers if they have a strategy and aren't already in the list
            if (userStrategies[actualUser].isActive && !_isUserInPool(actualUser, poolId)) {
                activeUsers[poolId].push(actualUser);
                poolStrategies[poolId].totalUsers++;
                poolStrategies[poolId].isActive = true;

                emit UserAddedToPool(actualUser, poolId, liquidityAdded);
            }

            // Update pool strategy
            if (userStrategies[actualUser].isActive) {
                poolStrategies[poolId].totalTVL += liquidityAdded;
            }
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
        PoolId poolId = key.toId();

        // Determine the actual user - either from hookData or sender
        address actualUser = sender;
        if (hookData.length > 0) {
            // Decode user address from hookData if provided
            actualUser = abi.decode(hookData, (address));
        }

        // Calculate liquidity removed from delta (use absolute values)
        uint256 liquidityRemoved = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0()))
            + uint256(int256(delta.amount1() > 0 ? delta.amount1() : -delta.amount1()));

        // Update user's liquidity position
        if (liquidityRemoved > 0) {
            UserLiquidityPosition storage position = userLiquidityPositions[actualUser][poolId];

            if (position.liquidityAmount >= liquidityRemoved) {
                position.liquidityAmount -= liquidityRemoved;
            } else {
                position.liquidityAmount = 0;
            }

            // Mark as inactive and remove from activeUsers if no liquidity left
            if (position.liquidityAmount == 0) {
                position.isActive = false;

                // Remove user from activeUsers array if they exist
                if (_isUserInPool(actualUser, poolId)) {
                    _removeUserFromPool(actualUser, poolId);
                    if (poolStrategies[poolId].totalUsers > 0) {
                        poolStrategies[poolId].totalUsers--;
                    }
                    emit UserRemovedFromPool(actualUser, poolId);
                }
            }

            position.lastUpdateTime = block.timestamp;

            // Update pool strategy
            if (userStrategies[actualUser].isActive) {
                if (poolStrategies[poolId].totalTVL >= liquidityRemoved) {
                    poolStrategies[poolId].totalTVL -= liquidityRemoved;
                } else {
                    poolStrategies[poolId].totalTVL = 0;
                }
            }
        }

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

    function getTotalPoolLiquidity(PoolId poolId) internal view returns (uint256) {
        uint256 totalLiquidity = 0;
        address[] memory users = activeUsers[poolId];

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (userLiquidityPositions[user][poolId].isActive) {
                totalLiquidity += userLiquidityPositions[user][poolId].liquidityAmount;
            }
        }

        return totalLiquidity;
    }

    function shouldCompound(address user, PoolId poolId) public view returns (bool) {
        UserStrategy memory strategy = userStrategies[user];
        FeeAccounting memory fees = userFees[user][poolId];

        // Check if user has strategy active
        if (!strategy.isActive) return false;

        // Check if enough fees accumulated
        if (fees.pendingCompound < MIN_COMPOUND_AMOUNT) return false;

        // Check if gas threshold met
        if (tx.gasprice > strategy.gasThreshold) return false;

        // Check if enough time passed (minimum 1 hour between compounds)
        if (block.timestamp < strategy.lastCompoundTime + MIN_ACTION_INTERVAL) return false;

        return true;
    }

    function compound(PoolId poolId) external {
        require(shouldCompound(msg.sender, poolId), "Cannot compound now");
        uint256 amount = userFees[msg.sender][poolId].pendingCompound;
        _executeCompound(msg.sender, poolId, amount);
    }

    function emergencyCompound(PoolId poolId) external {
        require(userStrategies[msg.sender].isActive, "Strategy not active");

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

        // Execute all compounds in batch
        for (uint256 i = 0; i < batch.length; i++) {
            PendingCompound memory pendingCompound = batch[i];

            // Execute individual compound
            _executeUserCompound(pendingCompound);
            totalAmount += pendingCompound.amount;
        }

        uint256 gasUsed = gasStart - gasleft();
        uint256 totalGasCost = gasUsed * tx.gasprice;

        // Distribute gas costs among users
        _distributeGasCosts(batch, totalGasCost);

        // Clear pending compounds
        delete pendingCompounds[poolId];

        emit BatchExecuted(poolId, batch.length, totalAmount, gasUsed);
    }

    function _executeUserCompound(PendingCompound memory pendingCompound) internal {
        // Reset user's pending compound amount
        userFees[pendingCompound.user][pendingCompound.poolId].pendingCompound = 0;

        // Execute the actual compound by adding liquidity back to pool
        _addLiquidityToPool(pendingCompound.user, pendingCompound.poolId, pendingCompound.amount);

        // Update user strategy
        userStrategies[pendingCompound.user].totalCompounded += pendingCompound.amount;
        userStrategies[pendingCompound.user].lastCompoundTime = block.timestamp;

        emit FeesCompounded(pendingCompound.user, pendingCompound.amount);
    }

    function _executeCompound(address user, PoolId poolId, uint256 amount) internal {
        // Reset pending compound amount
        userFees[user][poolId].pendingCompound = 0;

        // Execute compound by adding liquidity back to pool
        _addLiquidityToPool(user, poolId, amount);

        // Update user strategy
        userStrategies[user].totalCompounded += amount;
        userStrategies[user].lastCompoundTime = block.timestamp;

        emit FeesCompounded(user, amount);
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
}
