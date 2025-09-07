// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

/**
 * @title Deploy Uniswap V4 Infrastructure
 * @notice Sets up the complete Uniswap V4 environment on Anvil
 * @dev This script deploys PoolManager and essential infrastructure
 */
contract DeployV4Infrastructure is Script {
    using PoolIdLibrary for PoolKey;

    // Deployment addresses (will be populated during deployment)
    IPoolManager public poolManager;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying Uniswap V4 Infrastructure...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Chain ID:", block.chainid);
        
        // Deploy PoolManager - the core of Uniswap V4
        poolManager = new PoolManager(vm.addr(deployerPrivateKey));
        
        console.log("PoolManager deployed at:", address(poolManager));
        
        // Verify deployment
        require(address(poolManager) != address(0), "PoolManager deployment failed");
        
        console.log("\n=== UNISWAP V4 INFRASTRUCTURE DEPLOYED ===");
        console.log("PoolManager:", address(poolManager));
        console.log("Ready for hook integration!");
        
        vm.stopBroadcast();
        
        // Save deployment info to file for other scripts
        _saveDeploymentInfo();
    }
    
    function _saveDeploymentInfo() internal {
        string memory deploymentInfo = string.concat(
            "POOL_MANAGER=", vm.toString(address(poolManager)), "\n",
            "DEPLOYER=", vm.toString(vm.addr(vm.envUint("ANVIL_PRIVATE_KEY"))), "\n",
            "CHAIN_ID=", vm.toString(block.chainid), "\n"
        );
        
        vm.writeFile("./deployments/v4-infrastructure.env", deploymentInfo);
        console.log("Deployment info saved to: ./deployments/v4-infrastructure.env");
    }
}
