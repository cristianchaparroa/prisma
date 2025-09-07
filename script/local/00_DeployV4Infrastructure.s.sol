// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PositionDescriptor} from "v4-periphery/src/PositionDescriptor.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SimplePermit2} from "./mocks/SimplePermit2.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

/**
 * @title Deploy Uniswap V4 Infrastructure
 * @notice Sets up the complete Uniswap V4 environment on Anvil
 * @dev This script deploys PoolManager, PositionManager, and all dependencies
 */
contract DeployV4Infrastructure is Script {
    using PoolIdLibrary for PoolKey;

    // Deployment addresses (will be populated during deployment)
    IPoolManager public poolManager;
    PositionManager public positionManager;
    PositionDescriptor public positionDescriptor;
    IAllowanceTransfer public permit2;
    WETH public weth9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Uniswap V4 Infrastructure...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Chain ID:", block.chainid);

        // Deploy PoolManager - the core of Uniswap V4
        poolManager = new PoolManager(vm.addr(deployerPrivateKey));
        console.log("PoolManager deployed at:", address(poolManager));

        // Deploy our own Permit2 for local testing
        // Use a simple proxy that implements the required interface
        permit2 = new SimplePermit2();
        console.log("SimplePermit2 deployed at:", address(permit2));

        // Deploy WETH9 for wrapped ETH functionality
        weth9 = new WETH();
        console.log("WETH9 deployed at:", address(weth9));

        // Deploy PositionDescriptor for NFT metadata
        positionDescriptor = new PositionDescriptor(poolManager, address(weth9), bytes32("ETH"));
        console.log("PositionDescriptor deployed at:", address(positionDescriptor));

        // Deploy PositionManager - handles liquidity management with all dependencies
        positionManager = new PositionManager(
            poolManager,
            permit2,
            300_000, // unsubscribe gas limit
            positionDescriptor,
            IWETH9(address(weth9))
        );
        console.log("PositionManager deployed at:", address(positionManager));

        // Verify deployment
        require(address(poolManager) != address(0), "PoolManager deployment failed");
        require(address(permit2) != address(0), "SimplePermit2 deployment failed");
        require(address(weth9) != address(0), "WETH9 deployment failed");
        require(address(positionDescriptor) != address(0), "PositionDescriptor deployment failed");
        require(address(positionManager) != address(0), "PositionManager deployment failed");

        console.log("\n=== UNISWAP V4 INFRASTRUCTURE DEPLOYED ===");
        console.log("PoolManager:", address(poolManager));
        console.log("Permit2:", address(permit2));
        console.log("WETH9:", address(weth9));
        console.log("PositionDescriptor:", address(positionDescriptor));
        console.log("PositionManager:", address(positionManager));
        console.log("Ready for hook integration and liquidity provision!");

        vm.stopBroadcast();

        // Save deployment info to file for other scripts
        _saveDeploymentInfo();
    }

    function _saveDeploymentInfo() internal {
        string memory deploymentInfo = string.concat(
            "POOL_MANAGER=",
            vm.toString(address(poolManager)),
            "\n",
            "POSITION_MANAGER=",
            vm.toString(address(positionManager)),
            "\n",
            "PERMIT2=",
            vm.toString(address(permit2)),
            "\n",
            "WETH9=",
            vm.toString(address(weth9)),
            "\n",
            "POSITION_DESCRIPTOR=",
            vm.toString(address(positionDescriptor)),
            "\n",
            "DEPLOYER=",
            vm.toString(vm.addr(vm.envUint("ANVIL_PRIVATE_KEY"))),
            "\n",
            "CHAIN_ID=",
            vm.toString(block.chainid),
            "\n"
        );

        vm.writeFile("./deployments/v4-infrastructure.env", deploymentInfo);
        console.log("Deployment info saved to: ./deployments/v4-infrastructure.env");
    }
}
