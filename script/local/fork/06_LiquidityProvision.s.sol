// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * LiquidityAdder - Using V4 Periphery PositionManager (Correct Approach)
 *
 * This uses the official PositionManager which handles all the complex
 * sync/settle logic internally via the command system.
 */
contract LiquidityAdder {
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;

    constructor(address _positionManager, address _permit2) {
        positionManager = IPositionManager(_positionManager);
        permit2 = IAllowanceTransfer(_permit2);
    }

    function mintLiquidity(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address recipient,
        bytes calldata hookData
    ) external {
        // Prepare the command sequence
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](2);

        // MINT_POSITION parameters
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            recipient,
            hookData
        );

        // SETTLE_PAIR parameters
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        // Set deadline (1 hour from now)
        uint256 deadline = block.timestamp + 3600;

        // Execute the position creation (no ETH needed for ERC-20 tokens)
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            deadline
        );
    }
}

/* -------------------------------------------------------------------------- */
/* Forge Script: Deploy + Run                                                */
/* -------------------------------------------------------------------------- */

// Define struct outside the contract
    struct PoolConfig {
        address token0;
        address token1;
        uint128 amount0;
        uint128 amount1;
        string name;
    }

contract LiquidityProvision is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address positionManagerAddr = vm.envAddress("POSITION_MANAGER");
        address permit2Addr = vm.envAddress("PERMIT2");
        address tokenUSDC = vm.envAddress("TOKEN_USDC");
        address tokenWETH = vm.envAddress("TOKEN_WETH");
        address tokenDAI = vm.envAddress("TOKEN_DAI");
        address tokenWBTC = vm.envAddress("TOKEN_WBTC");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");

        uint24 fee = 3000;
        int24 tickSpacing = 60;
        int24 tickLower = -120;
        int24 tickUpper = 120;

        vm.startBroadcast(deployerKey);
        address deployer = vm.addr(deployerKey);

        console2.log("Deploying LiquidityAdder...");
        LiquidityAdder adder = new LiquidityAdder(positionManagerAddr, permit2Addr);
        console2.log("LiquidityAdder deployed at:", address(adder));

        // Set up Permit2 approvals for ALL tokens
        address[] memory tokens = new address[](4);
        tokens[0] = tokenUSDC;
        tokens[1] = tokenWETH;
        tokens[2] = tokenDAI;
        tokens[3] = tokenWBTC;

        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(permit2Addr, type(uint256).max);
            IAllowanceTransfer(permit2Addr).approve(
                tokens[i],
                positionManagerAddr,
                type(uint160).max,
                type(uint48).max
            );
        }
        console2.log("Permit2 approvals set for all tokens");

        // Define pool configurations with appropriate amounts
        PoolConfig[] memory pools = new PoolConfig[](4);

        // USDC/WETH pool
        pools[0] = PoolConfig({
            token0: tokenUSDC,
            token1: tokenWETH,
            amount0: 10_000e6,  // 10,000 USDC
            amount1: 5e18,      // 5 WETH
            name: "USDC/WETH"
        });

        // DAI/WETH pool
        pools[1] = PoolConfig({
            token0: tokenDAI,
            token1: tokenWETH,
            amount0: 10_000e18, // 10,000 DAI
            amount1: 5e18,      // 5 WETH
            name: "DAI/WETH"
        });

        // DAI/USDC pool
        pools[2] = PoolConfig({
            token0: tokenDAI,
            token1: tokenUSDC,
            amount0: 10_000e18, // 10,000 DAI
            amount1: 10_000e6,  // 10,000 USDC
            name: "DAI/USDC"
        });

        // WBTC/WETH pool
        pools[3] = PoolConfig({
            token0: tokenWBTC,
            token1: tokenWETH,
            amount0: 1e8,       // 1 WBTC
            amount1: 15e18,     // 15 WETH (approx BTC price ratio)
            name: "WBTC/WETH"
        });

        // Add liquidity to each pool
        for (uint i = 0; i < pools.length; i++) {
            PoolConfig memory poolConfig = pools[i];

            console2.log("Adding liquidity to", poolConfig.name);

            // Ensure correct currency ordering (currency0 < currency1)
            address currency0 = poolConfig.token0 < poolConfig.token1 ? poolConfig.token0 : poolConfig.token1;
            address currency1 = poolConfig.token0 < poolConfig.token1 ? poolConfig.token1 : poolConfig.token0;
            uint128 amount0Max = poolConfig.token0 < poolConfig.token1 ? poolConfig.amount0 : poolConfig.amount1;
            uint128 amount1Max = poolConfig.token0 < poolConfig.token1 ? poolConfig.amount1 : poolConfig.amount0;

            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(currency0),
                currency1: Currency.wrap(currency1),
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: IHooks(hookAddr)
            });

            bytes memory actions = abi.encodePacked(
                uint8(Actions.MINT_POSITION),
                uint8(Actions.SETTLE_PAIR)
            );

            bytes[] memory params = new bytes[](2);

            params[0] = abi.encode(
                key,
                tickLower,
                tickUpper,
                1000000, // 1M liquidity units per pool
                amount0Max,
                amount1Max,
                deployer,
                abi.encode(deployer)
            );

            params[1] = abi.encode(key.currency0, key.currency1);

            uint256 deadline = block.timestamp + 3600;

            try IPositionManager(positionManagerAddr).modifyLiquidities(
                abi.encode(actions, params),
                deadline
            ) {
                console2.log("Successfully added liquidity to", poolConfig.name);
            } catch Error(string memory reason) {
                console2.log("Failed to add liquidity to", poolConfig.name, ":", reason);
            }
        }

        vm.stopBroadcast();
    }
}
