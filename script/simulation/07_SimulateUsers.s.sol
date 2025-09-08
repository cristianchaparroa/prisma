// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {MockERC20} from "../local/01_CreateTokens.s.sol";
import {YieldMaximizerHook} from "../../src/YieldMaximizerHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title Simulate Diverse Users with Auto-Compound Strategies
 * @notice Creates 9 different user personas with varied risk profiles and strategy activations
 *         Each user activates ONE auto-compound strategy (hook limitation) but provides liquidity to multiple pools
 *         Builds on top of existing token distribution and pool infrastructure
 */
contract SimulateUsers is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts (loaded from existing deployment)
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    YieldMaximizerHook public yieldHook;

    // Token contracts (from existing deployment)
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;
    MockERC20 public yieldToken;

    // Test accounts (from existing distribution)
    address[] public testAccounts;
    uint256[] public testPrivateKeys;

    // User profile definitions
    struct UserProfile {
        string name;
        string riskProfile;
        uint8 riskLevel; // 1-10 scale for hook
        uint256 gasThreshold; // Max gas price (in gwei)
        PoolId[] preferredPools; // Pools this user will provide liquidity to
        uint256[] liquidityRatios; // Percentage of holdings to add to each pool
        bool isWhale; // Different behavior for whale users
    }

    // Pool configurations (from existing deployment)
    struct PoolConfig {
        string name;
        PoolKey poolKey;
        PoolId poolId;
        int24 tickSpacing;
        uint24 fee;
    }

    PoolConfig[] public poolConfigs;

    function run() external {
        // Load existing infrastructure
        _loadContracts();
        _loadTestAccounts();
        _loadPoolConfigurations();

        console.log("Starting User Simulation with Strategy Activation...");
        console.log(string.concat("Users to simulate: ", vm.toString(testAccounts.length - 1))); // Skip deployer account

        // Simulate each user (skip account 0 which is deployer)
        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            UserProfile memory profile = _getUserProfile(i);
            _simulateUser(i, profile);
        }

        console.log("\n USER SIMULATION COMPLETE!");
        console.log("Each user has one active auto-compound strategy on their primary pool");
        console.log("Diverse liquidity positions created");
        console.log("Ready for trading activity generation");

        // Save simulation info
        _saveSimulationInfo();
    }

    function _loadContracts() internal {
        console.log("Loading contracts from existing deployment...");

        // Load core contracts from environment
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER"));
        yieldHook = YieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));

        console.log(string.concat("  PoolManager: ", vm.toString(address(poolManager))));
        console.log(string.concat("  PositionManager: ", vm.toString(address(positionManager))));
        console.log(string.concat("  YieldMaximizerHook: ", vm.toString(address(yieldHook))));

        // Load token contracts
        weth = MockERC20(vm.envAddress("TOKEN_WETH"));
        usdc = MockERC20(vm.envAddress("TOKEN_USDC"));
        dai = MockERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = MockERC20(vm.envAddress("TOKEN_WBTC"));
        yieldToken = MockERC20(vm.envAddress("TOKEN_YIELD"));

        console.log("All contracts loaded successfully");
    }

    function _loadTestAccounts() internal {
        console.log("Loading test accounts from environment...");

        // Load test accounts and private keys
        testAccounts.push(vm.envAddress("ANVIL_ADDRESS")); // Account 0 (deployer)
        testPrivateKeys.push(vm.envUint("ANVIL_PRIVATE_KEY"));

        for (uint256 i = 1; i <= 9; i++) {
            try vm.envAddress(string.concat("ACCOUNT_", vm.toString(i), "_ADDRESS")) returns (address account) {
                testAccounts.push(account);
                uint256 privateKey = vm.envUint(string.concat("ACCOUNT_", vm.toString(i), "_PRIVATE_KEY"));
                testPrivateKeys.push(privateKey);
            } catch {
                console.log(
                    string.concat(
                        "Account ", vm.toString(i), " not found, stopping at ", vm.toString(i - 1), " accounts"
                    )
                );
                break;
            }
        }

        console.log(string.concat("  Loaded ", vm.toString(testAccounts.length), " test accounts"));
    }

    function _loadPoolConfigurations() internal {
        console.log("Loading pool configurations...");

        // WETH/USDC Pool
        PoolKey memory wethUsdcKey =
            _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), 3000, 60);
        poolConfigs.push(
            PoolConfig({name: "WETH/USDC", poolKey: wethUsdcKey, poolId: wethUsdcKey.toId(), tickSpacing: 60, fee: 3000})
        );

        // WETH/DAI Pool
        PoolKey memory wethDaiKey = _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(dai)), 3000, 60);
        poolConfigs.push(
            PoolConfig({name: "WETH/DAI", poolKey: wethDaiKey, poolId: wethDaiKey.toId(), tickSpacing: 60, fee: 3000})
        );

        // USDC/DAI Pool (Stablecoin)
        PoolKey memory usdcDaiKey = _createPoolKey(Currency.wrap(address(usdc)), Currency.wrap(address(dai)), 500, 10);
        poolConfigs.push(
            PoolConfig({name: "USDC/DAI", poolKey: usdcDaiKey, poolId: usdcDaiKey.toId(), tickSpacing: 10, fee: 500})
        );

        // WBTC/WETH Pool
        PoolKey memory wbtcWethKey =
            _createPoolKey(Currency.wrap(address(wbtc)), Currency.wrap(address(weth)), 3000, 60);
        poolConfigs.push(
            PoolConfig({name: "WBTC/WETH", poolKey: wbtcWethKey, poolId: wbtcWethKey.toId(), tickSpacing: 60, fee: 3000})
        );

        // YIELD/WETH Pool
        PoolKey memory yieldWethKey =
            _createPoolKey(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth)), 10000, 200);
        poolConfigs.push(
            PoolConfig({
                name: "YIELD/WETH",
                poolKey: yieldWethKey,
                poolId: yieldWethKey.toId(),
                tickSpacing: 200,
                fee: 10000
            })
        );

        console.log(string.concat("Loaded ", vm.toString(poolConfigs.length), " pool configurations"));
    }

    function _getUserProfile(uint256 accountIndex) internal view returns (UserProfile memory) {
        PoolId[] memory pools;
        uint256[] memory ratios;

        if (accountIndex >= 1 && accountIndex <= 3) {
            // Conservative users (accounts 1-3): Focus on stablecoins and major pairs
            pools = new PoolId[](2);
            ratios = new uint256[](2);
            pools[0] = poolConfigs[2].poolId; // USDC/DAI
            pools[1] = poolConfigs[0].poolId; // WETH/USDC
            ratios[0] = 60; // 60% in stablecoin pair
            ratios[1] = 40; // 40% in WETH/USDC

            return UserProfile({
                name: string.concat("Conservative_User_", vm.toString(accountIndex)),
                riskProfile: "conservative",
                riskLevel: 2,
                gasThreshold: 20 gwei, // Low gas tolerance
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: false
            });
        } else if (accountIndex >= 4 && accountIndex <= 6) {
            // Moderate users (accounts 4-6): Balanced approach
            pools = new PoolId[](3);
            ratios = new uint256[](3);
            pools[0] = poolConfigs[0].poolId; // WETH/USDC
            pools[1] = poolConfigs[1].poolId; // WETH/DAI
            pools[2] = poolConfigs[2].poolId; // USDC/DAI
            ratios[0] = 40; // 40% in WETH/USDC
            ratios[1] = 35; // 35% in WETH/DAI
            ratios[2] = 25; // 25% in stablecoins

            return UserProfile({
                name: string.concat("Moderate_User_", vm.toString(accountIndex)),
                riskProfile: "moderate",
                riskLevel: 5,
                gasThreshold: 50 gwei, // Medium gas tolerance
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: false
            });
        } else if (accountIndex >= 7 && accountIndex <= 8) {
            // Aggressive users (accounts 7-8): High risk, high reward
            pools = new PoolId[](3);
            ratios = new uint256[](3);
            pools[0] = poolConfigs[3].poolId; // WBTC/WETH
            pools[1] = poolConfigs[4].poolId; // YIELD/WETH
            pools[2] = poolConfigs[0].poolId; // WETH/USDC
            ratios[0] = 40; // 40% in WBTC/WETH
            ratios[1] = 35; // 35% in YIELD/WETH
            ratios[2] = 25; // 25% in WETH/USDC

            return UserProfile({
                name: string.concat("Aggressive_User_", vm.toString(accountIndex)),
                riskProfile: "aggressive",
                riskLevel: 8,
                gasThreshold: 100 gwei, // High gas tolerance
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: false
            });
        } else {
            // Whale user (account 9): Diversified across all pools
            pools = new PoolId[](5);
            ratios = new uint256[](5);
            pools[0] = poolConfigs[0].poolId; // WETH/USDC
            pools[1] = poolConfigs[1].poolId; // WETH/DAI
            pools[2] = poolConfigs[2].poolId; // USDC/DAI
            pools[3] = poolConfigs[3].poolId; // WBTC/WETH
            pools[4] = poolConfigs[4].poolId; // YIELD/WETH
            ratios[0] = 25; // 25% in each major pool
            ratios[1] = 25;
            ratios[2] = 20;
            ratios[3] = 15;
            ratios[4] = 15;

            return UserProfile({
                name: "Whale_User_9",
                riskProfile: "whale",
                riskLevel: 6,
                gasThreshold: 75 gwei, // High gas tolerance
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: true
            });
        }
    }

    function _simulateUser(uint256 accountIndex, UserProfile memory profile) internal {
        console.log(string.concat("\nSimulating user: ", profile.name));
        console.log(string.concat("  Risk Profile: ", profile.riskProfile));
        console.log(string.concat("  Risk Level: ", vm.toString(profile.riskLevel)));
        console.log(string.concat("  Gas Threshold: ", vm.toString(profile.gasThreshold / 1 gwei), " gwei"));
        console.log(string.concat("  Preferred Pools: ", vm.toString(profile.preferredPools.length)));

        address userAddress = testAccounts[accountIndex];
        uint256 userPrivateKey = testPrivateKeys[accountIndex];

        vm.startBroadcast(userPrivateKey);

        // 1. Activate strategy for each preferred pool
        // 1. Activate strategy for the user's primary pool only (hook limitation: one strategy per user)
        PoolId primaryPoolId = profile.preferredPools[0]; // Use first pool as primary

        console.log(string.concat("  Activating strategy for primary pool: ", _getPoolName(primaryPoolId)));

        yieldHook.activateStrategy(primaryPoolId, profile.gasThreshold, profile.riskLevel);

        // 2. Provide liquidity to preferred pools
        for (uint256 i = 0; i < profile.preferredPools.length; i++) {
            PoolId poolId = profile.preferredPools[i];
            uint256 liquidityRatio = profile.liquidityRatios[i];

            _provideLiquidityForUser(userAddress, poolId, liquidityRatio, profile.isWhale);
        }

        vm.stopBroadcast();

        console.log("User simulation completed");
    }

    function _provideLiquidityForUser(address user, PoolId poolId, uint256 ratio, bool isWhale) internal {
        PoolConfig memory poolConfig = _getPoolConfig(poolId);
        console.log(
            string.concat("    Adding liquidity to ", poolConfig.name, " with ", vm.toString(ratio), "% allocation")
        );

        // Calculate amounts based on user's token holdings and allocation ratio
        (uint256 amount0, uint256 amount1) = _calculateUserLiquidityAmounts(user, poolConfig, ratio, isWhale);

        if (amount0 == 0 || amount1 == 0) {
            console.log("Insufficient tokens for liquidity provision");
            return;
        }

        // Approve tokens for PositionManager
        _approveTokensForUser(poolConfig.poolKey.currency0, poolConfig.poolKey.currency1, amount0, amount1);

        // Calculate tick range for position
        (int24 tickLower, int24 tickUpper) = _calculateTickRange(poolConfig, isWhale);

        // Mint position using PositionManager
        _mintUserPosition(poolConfig.poolKey, tickLower, tickUpper, amount0, amount1, user);

        console.log("Liquidity added successfully");
    }

    function _calculateUserLiquidityAmounts(address user, PoolConfig memory poolConfig, uint256 ratio, bool isWhale)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        Currency currency0 = poolConfig.poolKey.currency0;
        Currency currency1 = poolConfig.poolKey.currency1;

        // Get user's token balances
        uint256 balance0 = IERC20(Currency.unwrap(currency0)).balanceOf(user);
        uint256 balance1 = IERC20(Currency.unwrap(currency1)).balanceOf(user);

        if (isWhale) {
            // Whale users provide more liquidity
            amount0 = (balance0 * ratio) / 100;
            amount1 = (balance1 * ratio) / 100;
        } else {
            // Regular users provide conservative amounts
            amount0 = (balance0 * ratio) / 200; // Use half of the ratio
            amount1 = (balance1 * ratio) / 200;
        }

        // Ensure minimum liquidity amounts
        uint256 minAmount = isWhale ? 1000 : 100; // Different minimums for whales vs regular users

        if (Currency.unwrap(currency0) == address(usdc)) {
            amount0 = amount0 < minAmount * 10 ** 6 ? minAmount * 10 ** 6 : amount0;
        } else {
            amount0 = amount0 < minAmount * 10 ** 18 ? minAmount * 10 ** 18 : amount0;
        }

        if (Currency.unwrap(currency1) == address(usdc)) {
            amount1 = amount1 < minAmount * 10 ** 6 ? minAmount * 10 ** 6 : amount1;
        } else {
            amount1 = amount1 < minAmount * 10 ** 18 ? minAmount * 10 ** 18 : amount1;
        }
    }

    function _approveTokensForUser(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1) internal {
        // Approve tokens for Permit2 (used by PositionManager)
        address permit2Address = vm.envAddress("PERMIT2");

        IERC20(Currency.unwrap(currency0)).approve(permit2Address, amount0);
        IERC20(Currency.unwrap(currency1)).approve(permit2Address, amount1);
    }

    function _calculateTickRange(PoolConfig memory poolConfig, bool isWhale)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        int24 tickSpacing = poolConfig.tickSpacing;

        if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("WETH/USDC")) {
            tickLower = isWhale ? int24(-1200) : int24(-600); // Whales provide wider ranges
            tickUpper = isWhale ? int24(1200) : int24(600);
        } else if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("WETH/DAI")) {
            tickLower = isWhale ? int24(-1200) : int24(-600);
            tickUpper = isWhale ? int24(1200) : int24(600);
        } else if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("USDC/DAI")) {
            // Tighter range for stablecoin pair
            tickLower = isWhale ? int24(-200) : int24(-100);
            tickUpper = isWhale ? int24(200) : int24(100);
        } else if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("WBTC/WETH")) {
            tickLower = isWhale ? int24(-1200) : int24(-600);
            tickUpper = isWhale ? int24(1200) : int24(600);
        } else {
            // YIELD/WETH - wider range for new token
            tickLower = isWhale ? int24(-2000) : int24(-1000);
            tickUpper = isWhale ? int24(2000) : int24(1000);
        }

        // Align to tick spacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        // Ensure valid range
        require(tickLower < tickUpper, "Invalid tick range");
        require(tickLower >= -887272 && tickUpper <= 887272, "Tick out of bounds");
    }

    function _mintUserPosition(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient
    ) internal {
        // Use PositionManager.modifyLiquidities() to mint position
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);

        // MINT_POSITION parameters
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            uint256(100000), // liquidity amount - smaller for users than initial deployment
            amount0Max,
            amount1Max,
            recipient,
            bytes("") // hookData
        );

        // SETTLE_PAIR parameters
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        bytes memory unlockData = abi.encode(actions, params);

        // Execute via modifyLiquidities
        positionManager.modifyLiquidities(unlockData, block.timestamp + 60);
    }

    function _saveSimulationInfo() internal {
        console.log("\n Saving simulation information...");

        string memory simulationInfo = "# User Simulation Results\n";
        simulationInfo =
            string.concat(simulationInfo, "TOTAL_SIMULATED_USERS=", vm.toString(testAccounts.length - 1), "\n");
        simulationInfo = string.concat(simulationInfo, "CONSERVATIVE_USERS=3\n");
        simulationInfo = string.concat(simulationInfo, "MODERATE_USERS=3\n");
        simulationInfo = string.concat(simulationInfo, "AGGRESSIVE_USERS=2\n");
        simulationInfo = string.concat(simulationInfo, "WHALE_USERS=1\n");
        simulationInfo = string.concat(simulationInfo, "TOTAL_POOLS_WITH_USERS=5\n");
        simulationInfo = string.concat(simulationInfo, "SIMULATION_TIMESTAMP=", vm.toString(block.timestamp), "\n");

        // Add user details
        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            UserProfile memory profile = _getUserProfile(i);
            simulationInfo =
                string.concat(simulationInfo, "USER_", vm.toString(i), "_ADDRESS=", vm.toString(testAccounts[i]), "\n");
            simulationInfo =
                string.concat(simulationInfo, "USER_", vm.toString(i), "_PROFILE=", profile.riskProfile, "\n");
            simulationInfo = string.concat(
                simulationInfo, "USER_", vm.toString(i), "_RISK_LEVEL=", vm.toString(profile.riskLevel), "\n"
            );
            simulationInfo = string.concat(
                simulationInfo, "USER_", vm.toString(i), "_POOLS=", vm.toString(profile.preferredPools.length), "\n"
            );
        }

        vm.writeFile("./deployments/simulation-users.env", simulationInfo);
        console.log("Simulation info saved to: ./deployments/simulation-users.env");
    }

    // Helper functions
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

    function _getPoolConfig(PoolId poolId) internal view returns (PoolConfig memory) {
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            if (PoolId.unwrap(poolConfigs[i].poolId) == PoolId.unwrap(poolId)) {
                return poolConfigs[i];
            }
        }
        revert("Pool config not found");
    }

    function _getPoolName(PoolId poolId) internal view returns (string memory) {
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            if (PoolId.unwrap(poolConfigs[i].poolId) == PoolId.unwrap(poolId)) {
                return poolConfigs[i].name;
            }
        }
        return "Unknown Pool";
    }
}
