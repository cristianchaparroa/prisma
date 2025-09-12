// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {YieldMaximizerHook} from "../../../src/YieldMaximizerHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/**
 * @title Simulate Diverse Users with Auto-Compound Strategies
 * @notice Creates 9 different user personas with varied risk profiles and strategy activations.
 *         Each user activates ONE auto-compound strategy (hook limitation) but can LP in multiple pools.
 */
contract SimulateUsers is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts (loaded from env)
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    YieldMaximizerHook public yieldHook;

    // Tokens
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;
    // IERC20 public yieldToken; // optional, loaded if TOKEN_YIELD is set
    bool public hasYieldToken;

    // Test accounts
    address[] public testAccounts;
    uint256[] public testPrivateKeys;

    // User profile definitions
    struct UserProfile {
        string name;
        string riskProfile;
        uint8 riskLevel; // 1-10
        uint256 gasThreshold; // in gwei
        PoolId[] preferredPools; // pools to LP
        uint256[] liquidityRatios; // % allocations per pool
        bool isWhale;
    }

    // Pool configurations
    struct PoolConfig {
        string name;
        PoolKey poolKey;
        PoolId poolId;
        int24 tickSpacing;
        uint24 fee;
    }

    PoolConfig[] public poolConfigs;
    // indexes for quick reference
    uint256 private idxWethUsdc;
    uint256 private idxWethDai;
    uint256 private idxUsdcDai;
    uint256 private idxWbtcWeth;
    uint256 private idxYieldWeth; // only valid if hasYieldToken

    /* ---------------------------
       ENTRY
       --------------------------- */
    function run() external {
        _loadContracts();
        _loadTestAccounts();
        _loadPoolConfigurations();

        console.log(string.concat("Starting User Simulation with Strategy Activation..."));
        console.log(string.concat("Users to simulate: ", vm.toString(testAccounts.length - 1))); // skip deployer

        for (uint256 i = 1; i < testAccounts.length && i < 10; i++) {
            UserProfile memory profile = _getUserProfile(i);
            _simulateUser(i, profile);
        }

        console.log(string.concat("\nUSER SIMULATION COMPLETE!"));
        _saveSimulationInfo();
    }

    /* ---------------------------
       SETUP / LOADING
       --------------------------- */
    function _loadContracts() internal {
        console.log("Loading contracts from existing deployment...");

        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER"));
        yieldHook = YieldMaximizerHook(vm.envAddress("HOOK_ADDRESS"));

        weth = IERC20(vm.envAddress("TOKEN_WETH"));
        usdc = IERC20(vm.envAddress("TOKEN_USDC"));
        dai = IERC20(vm.envAddress("TOKEN_DAI"));
        wbtc = IERC20(vm.envAddress("TOKEN_WBTC"));

        // Optional YIELD token (only if env present)
        //        try vm.envAddress("TOKEN_YIELD") returns (address y) {
        //            if (y != address(0)) {
        //                yieldToken = IERC20(y);
        //                hasYieldToken = true;
        //            } else {
        //                hasYieldToken = false;
        //            }
        //        } catch {
        //            hasYieldToken = false;
        //        }

        console.log(string.concat("  PoolManager:        ", vm.toString(address(poolManager))));
        console.log(string.concat("  PositionManager:    ", vm.toString(address(positionManager))));
        console.log(string.concat("  YieldMaximizerHook: ", vm.toString(address(yieldHook))));
        console.log(string.concat("  WETH:               ", vm.toString(address(weth))));
        console.log(string.concat("  USDC:               ", vm.toString(address(usdc))));
        console.log(string.concat("  DAI:                ", vm.toString(address(dai))));
        console.log(string.concat("  WBTC:               ", vm.toString(address(wbtc))));
        //        if (hasYieldToken) {
        //            console.log(string.concat("  YIELD:              ", vm.toString(address(yieldToken))));
        //        }
    }

    function _loadTestAccounts() internal {
        console.log("Loading test accounts from environment...");

        testAccounts.push(vm.envAddress("ANVIL_ADDRESS")); // 0 - deployer
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

        // WETH/USDC 0.3% / 60
        PoolKey memory wethUsdcKey =
            _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), 3000, 60);
        idxWethUsdc = poolConfigs.length;
        poolConfigs.push(PoolConfig("WETH/USDC", wethUsdcKey, wethUsdcKey.toId(), 60, 3000));

        // WETH/DAI 0.3% / 60
        PoolKey memory wethDaiKey = _createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(dai)), 3000, 60);
        idxWethDai = poolConfigs.length;
        poolConfigs.push(PoolConfig("WETH/DAI", wethDaiKey, wethDaiKey.toId(), 60, 3000));

        // USDC/DAI 0.05% / 10
        PoolKey memory usdcDaiKey = _createPoolKey(Currency.wrap(address(usdc)), Currency.wrap(address(dai)), 500, 10);
        idxUsdcDai = poolConfigs.length;
        poolConfigs.push(PoolConfig("USDC/DAI", usdcDaiKey, usdcDaiKey.toId(), 10, 500));

        // WBTC/WETH 0.3% / 60
        PoolKey memory wbtcWethKey =
            _createPoolKey(Currency.wrap(address(wbtc)), Currency.wrap(address(weth)), 3000, 60);
        idxWbtcWeth = poolConfigs.length;
        poolConfigs.push(PoolConfig("WBTC/WETH", wbtcWethKey, wbtcWethKey.toId(), 60, 3000));

        // Optional YIELD/WETH 1% / 200 (only if TOKEN_YIELD provided)
        //        if (hasYieldToken) {
        //            PoolKey memory yieldWethKey = _createPoolKey(Currency.wrap(address(yieldToken)), Currency.wrap(address(weth)), 10_000, 200);
        //            idxYieldWeth = poolConfigs.length;
        //            poolConfigs.push(PoolConfig("YIELD/WETH", yieldWethKey, yieldWethKey.toId(), 200, 10_000));
        //        }

        console.log(string.concat("Loaded ", vm.toString(poolConfigs.length), " pool configurations"));
    }

    /* ---------------------------
       USER SIM
       --------------------------- */
    function _simulateUser(uint256 accountIndex, UserProfile memory profile) internal {
        console.log(string.concat("\nSimulating user: ", profile.name));
        console.log(string.concat("  Risk Profile: ", profile.riskProfile));
        console.log(string.concat("  Risk Level: ", vm.toString(profile.riskLevel)));
        console.log(string.concat("  Gas Threshold: ", vm.toString(profile.gasThreshold / 1 gwei), " gwei"));
        console.log(string.concat("  Preferred Pools: ", vm.toString(profile.preferredPools.length)));

        address userAddress = testAccounts[accountIndex];
        uint256 userPrivateKey = testPrivateKeys[accountIndex];

        vm.startBroadcast(userPrivateKey);

        // Check if strategy is already active before activating
        PoolId primaryPoolId = profile.preferredPools[0];
        console.log(string.concat("  Checking strategy for primary pool: ", _getPoolName(primaryPoolId)));

        // Get current user strategy to check if already active
        YieldMaximizerHook.UserStrategy memory currentStrategy = yieldHook.getUserStrategy(userAddress);

        if (currentStrategy.isActive) {
            console.log("  Strategy already active - updating parameters instead");
            yieldHook.updateStrategy(profile.gasThreshold, profile.riskLevel);
        } else {
            console.log("  Activating new strategy");
            yieldHook.activateStrategy(primaryPoolId, profile.gasThreshold, profile.riskLevel);
        }

        // Provide liquidity across preferred pools
        for (uint256 i = 0; i < profile.preferredPools.length; i++) {
            _provideLiquidityForUser(
                userAddress, profile.preferredPools[i], profile.liquidityRatios[i], profile.isWhale
            );
        }

        vm.stopBroadcast();

        console.log("User simulation completed");
    }

    function _provideLiquidityForUser(address user, PoolId poolId, uint256 ratio, bool isWhale) internal {
        PoolConfig memory poolConfig = _getPoolConfig(poolId);

        console.log(
            string.concat("    Adding liquidity to ", poolConfig.name, " with ", vm.toString(ratio), "% allocation")
        );

        (uint256 amount0, uint256 amount1) = _calculateUserLiquidityAmounts(user, poolConfig, ratio, isWhale);

        uint256 bal0 = IERC20(Currency.unwrap(poolConfig.poolKey.currency0)).balanceOf(user);
        uint256 bal1 = IERC20(Currency.unwrap(poolConfig.poolKey.currency1)).balanceOf(user);
        console.log(string.concat("    Bal0: ", vm.toString(bal0), " Bal1: ", vm.toString(bal1)));
        console.log(string.concat("    Using amounts0/1: ", vm.toString(amount0), " / ", vm.toString(amount1)));

        if (amount0 == 0 || amount1 == 0) {
            console.log("Insufficient tokens for liquidity provision, skipping");
            return;
        }

        // Approve Permit2 + PositionManager (performed by the user's account due to startBroadcast)
        _approveTokensForUser(poolConfig.poolKey.currency0, poolConfig.poolKey.currency1);

        (int24 tickLower, int24 tickUpper) = _calculateTickRange(poolConfig, isWhale);

        _mintUserPosition(poolConfig.poolKey, tickLower, tickUpper, amount0, amount1, user);

        console.log("Liquidity added");
    }

    function _calculateUserLiquidityAmounts(address user, PoolConfig memory poolConfig, uint256 ratio, bool isWhale)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        Currency c0 = poolConfig.poolKey.currency0;
        Currency c1 = poolConfig.poolKey.currency1;

        uint256 b0 = IERC20(Currency.unwrap(c0)).balanceOf(user);
        uint256 b1 = IERC20(Currency.unwrap(c1)).balanceOf(user);

        // Base allocation
        uint256 divisor = isWhale ? 100 : 200; // whales allocate "ratio%" of balance, regular users "ratio/2%"
        amount0 = (b0 * ratio) / divisor;
        amount1 = (b1 * ratio) / divisor;

        // Apply minimums by token decimals (USDC: 6, WBTC: 8, most others: 18)
        amount0 = _applyMin(amount0, Currency.unwrap(c0));
        amount1 = _applyMin(amount1, Currency.unwrap(c1));

        // Clamp to balance
        if (amount0 > b0) amount0 = b0;
        if (amount1 > b1) amount1 = b1;
    }

    function _applyMin(uint256 amt, address token) internal view returns (uint256) {
        // reasonable minimums
        uint256 minNormal = 100; // 100 units (in token native decimals)
        // use minNormal as baseline to avoid tiny amounts
        if (token == address(usdc)) {
            uint256 m = minNormal * 1e6;
            return amt < m ? m : amt;
        } else if (token == address(wbtc)) {
            uint256 m = minNormal * 1e8;
            return amt < m ? m : amt;
        } else {
            uint256 m = minNormal * 1e18;
            return amt < m ? m : amt;
        }
    }

    function _approveTokensForUser(Currency currency0, Currency currency1) internal {
        // Approve underlying ERC20 -> Permit2 with unlimited allowance (called by user due to startBroadcast)
        address permit2Address = vm.envAddress("PERMIT2");

        IERC20(Currency.unwrap(currency0)).approve(permit2Address, type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(permit2Address, type(uint256).max);

        // Also approve PositionManager as spender in Permit2 with MAX + far future expiry
        IPermit2 permit2 = IPermit2(permit2Address);
        permit2.approve(Currency.unwrap(currency0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency1), address(positionManager), type(uint160).max, type(uint48).max);
    }

    function _calculateTickRange(PoolConfig memory poolConfig, bool isWhale)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        int24 spacing = poolConfig.tickSpacing;

        if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("USDC/DAI")) {
            // stable, tighter
            tickLower = isWhale ? int24(-200) : int24(-100);
            tickUpper = isWhale ? int24(200) : int24(100);
        } else if (keccak256(abi.encodePacked(poolConfig.name)) == keccak256("YIELD/WETH")) {
            // wider for new token
            tickLower = isWhale ? int24(-2000) : int24(-1000);
            tickUpper = isWhale ? int24(2000) : int24(1000);
        } else {
            // majors
            tickLower = isWhale ? int24(-1200) : int24(-600);
            tickUpper = isWhale ? int24(1200) : int24(600);
        }

        // Align to spacing
        tickLower = spacing * (tickLower / spacing);
        tickUpper = spacing * (tickUpper / spacing);

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
        // PositionManager.modifyLiquidities: pack actions + params
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        // MINT_POSITION params
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            uint256(100000), // liquidity amount (smaller than bootstrap)
            amount0Max,
            amount1Max,
            recipient,
            abi.encode(recipient) // hookData
        );

        // SETTLE_PAIR params
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        // Execute
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 60);
    }

    /* ---------------------------
       USER PROFILE CONSTRUCTION
       --------------------------- */
    function _getUserProfile(uint256 accountIndex) internal view returns (UserProfile memory) {
        // helper to build dynamic arrays
        if (accountIndex >= 1 && accountIndex <= 3) {
            // Conservative: stable + majors
            uint256 n = 2;
            PoolId[] memory pools = new PoolId[](n);
            uint256[] memory ratios = new uint256[](n);
            pools[0] = poolConfigs[idxUsdcDai].poolId; // USDC/DAI
            pools[1] = poolConfigs[idxWethUsdc].poolId; // WETH/USDC
            ratios[0] = 60;
            ratios[1] = 40;

            return UserProfile({
                name: string.concat("Conservative_User_", vm.toString(accountIndex)),
                riskProfile: "conservative",
                riskLevel: 2,
                gasThreshold: 20 gwei,
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: false
            });
        } else if (accountIndex >= 4 && accountIndex <= 6) {
            // Moderate: diversified majors + stable
            uint256 n = 3;
            PoolId[] memory pools = new PoolId[](n);
            uint256[] memory ratios = new uint256[](n);
            pools[0] = poolConfigs[idxWethUsdc].poolId; // 40
            pools[1] = poolConfigs[idxWethDai].poolId; // 35
            pools[2] = poolConfigs[idxUsdcDai].poolId; // 25
            ratios[0] = 40;
            ratios[1] = 35;
            ratios[2] = 25;

            return UserProfile({
                name: string.concat("Moderate_User_", vm.toString(accountIndex)),
                riskProfile: "moderate",
                riskLevel: 5,
                gasThreshold: 50 gwei,
                preferredPools: pools,
                liquidityRatios: ratios,
                isWhale: false
            });
        } else if (accountIndex >= 7 && accountIndex <= 8) {
            // Aggressive: BTC/ETH + (optional) YIELD/WETH + WETH/USDC
            if (hasYieldToken) {
                uint256 n = 3;
                PoolId[] memory pools = new PoolId[](n);
                uint256[] memory ratios = new uint256[](n);
                pools[0] = poolConfigs[idxWbtcWeth].poolId; // 40
                pools[1] = poolConfigs[idxYieldWeth].poolId; // 35
                pools[2] = poolConfigs[idxWethUsdc].poolId; // 25
                ratios[0] = 40;
                ratios[1] = 35;
                ratios[2] = 25;

                return UserProfile({
                    name: string.concat("Aggressive_User_", vm.toString(accountIndex)),
                    riskProfile: "aggressive",
                    riskLevel: 8,
                    gasThreshold: 100 gwei,
                    preferredPools: pools,
                    liquidityRatios: ratios,
                    isWhale: false
                });
            } else {
                // fallback if YIELD not available
                uint256 n = 3;
                PoolId[] memory pools = new PoolId[](n);
                uint256[] memory ratios = new uint256[](n);
                pools[0] = poolConfigs[idxWbtcWeth].poolId;
                pools[1] = poolConfigs[idxWethUsdc].poolId;
                pools[2] = poolConfigs[idxWethDai].poolId;
                ratios[0] = 45;
                ratios[1] = 35;
                ratios[2] = 20;

                return UserProfile({
                    name: string.concat("Aggressive_User_", vm.toString(accountIndex)),
                    riskProfile: "aggressive",
                    riskLevel: 8,
                    gasThreshold: 100 gwei,
                    preferredPools: pools,
                    liquidityRatios: ratios,
                    isWhale: false
                });
            }
        } else {
            // Whale (acct 9)
            if (hasYieldToken) {
                uint256 n = 5;
                PoolId[] memory pools = new PoolId[](n);
                uint256[] memory ratios = new uint256[](n);
                pools[0] = poolConfigs[idxWethUsdc].poolId; // 25
                pools[1] = poolConfigs[idxWethDai].poolId; // 25
                pools[2] = poolConfigs[idxUsdcDai].poolId; // 20
                pools[3] = poolConfigs[idxWbtcWeth].poolId; // 15
                pools[4] = poolConfigs[idxYieldWeth].poolId; // 15
                ratios[0] = 25;
                ratios[1] = 25;
                ratios[2] = 20;
                ratios[3] = 15;
                ratios[4] = 15;

                return UserProfile({
                    name: "Whale_User_9",
                    riskProfile: "whale",
                    riskLevel: 6,
                    gasThreshold: 75 gwei,
                    preferredPools: pools,
                    liquidityRatios: ratios,
                    isWhale: true
                });
            } else {
                uint256 n = 4;
                PoolId[] memory pools = new PoolId[](n);
                uint256[] memory ratios = new uint256[](n);
                pools[0] = poolConfigs[idxWethUsdc].poolId; // 30
                pools[1] = poolConfigs[idxWethDai].poolId; // 30
                pools[2] = poolConfigs[idxUsdcDai].poolId; // 20
                pools[3] = poolConfigs[idxWbtcWeth].poolId; // 20
                ratios[0] = 30;
                ratios[1] = 30;
                ratios[2] = 20;
                ratios[3] = 20;

                return UserProfile({
                    name: "Whale_User_9",
                    riskProfile: "whale",
                    riskLevel: 6,
                    gasThreshold: 75 gwei,
                    preferredPools: pools,
                    liquidityRatios: ratios,
                    isWhale: true
                });
            }
        }
    }

    /* ---------------------------
       SAVE INFO
       --------------------------- */
    function _saveSimulationInfo() internal {
        console.log(string.concat("\nSaving simulation information..."));

        string memory simulationInfo = "# User Simulation Results\n";
        simulationInfo =
            string.concat(simulationInfo, "TOTAL_SIMULATED_USERS=", vm.toString(testAccounts.length - 1), "\n");
        simulationInfo = string.concat(simulationInfo, "CONSERVATIVE_USERS=3\n");
        simulationInfo = string.concat(simulationInfo, "MODERATE_USERS=3\n");
        simulationInfo = string.concat(simulationInfo, "AGGRESSIVE_USERS=2\n");
        simulationInfo = string.concat(simulationInfo, "WHALE_USERS=1\n");
        simulationInfo = string.concat(simulationInfo, "TOTAL_POOLS_WITH_USERS=", vm.toString(poolConfigs.length), "\n");
        simulationInfo = string.concat(simulationInfo, "SIMULATION_TIMESTAMP=", vm.toString(block.timestamp), "\n");
        simulationInfo = string.concat(simulationInfo, "HAS_YIELD_TOKEN=", hasYieldToken ? "true\n" : "false\n");

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
        console.log(string.concat("Simulation info saved to: ./deployments/simulation-users.env"));
    }

    /* ---------------------------
       HELPERS
       --------------------------- */
    function _createPoolKey(Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing)
        internal
        view
        returns (PoolKey memory)
    {
        // sort currencies
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
