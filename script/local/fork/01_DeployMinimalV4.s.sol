// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PositionDescriptor} from "v4-periphery/src/PositionDescriptor.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

contract DeployMinimalV4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address permit2 = vm.envAddress("PERMIT2"); // Use real Permit2
        address weth = vm.envAddress("TOKEN_WETH"); // Use real WETH

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Deploying V4 Infrastructure for fork...");
        console2.log("Deployer:", deployer);
        console2.log("Using real Permit2:", permit2);
        console2.log("Using real WETH:", weth);

        // Use official Uniswap V4 mainnet PoolManager (for mainnet fork)
        address poolManagerAddress = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        PoolManager poolManager = PoolManager(poolManagerAddress);
        console2.log("Using official PoolManager at:", address(poolManager));

        // Deploy PositionDescriptor for NFT metadata
        PositionDescriptor positionDescriptor = new PositionDescriptor(poolManager, weth, bytes32("ETH"));
        console2.log("PositionDescriptor deployed at:", address(positionDescriptor));

        // Deploy PositionManager with all required parameters
        PositionManager positionManager = new PositionManager(
            poolManager,
            IAllowanceTransfer(permit2),
            300_000, // Unsubscribe gas limit
            positionDescriptor,
            IWETH9(weth)
        );
        console2.log("PositionManager deployed at:", address(positionManager));

        // Verify deployment
        require(address(poolManager) != address(0), "PoolManager deployment failed");
        require(address(positionDescriptor) != address(0), "PositionDescriptor deployment failed");
        require(address(positionManager) != address(0), "PositionManager deployment failed");

        vm.stopBroadcast();

        // Save deployment addresses
        string memory deployments = string.concat(
            "POOL_MANAGER=",
            vm.toString(address(poolManager)),
            "\n",
            "POSITION_MANAGER=",
            vm.toString(address(positionManager)),
            "\n",
            "POSITION_DESCRIPTOR=",
            vm.toString(address(positionDescriptor)),
            "\n",
            "PERMIT2=",
            vm.toString(permit2),
            "\n",
            "WETH9=",
            vm.toString(weth),
            "\n",
            "DEPLOYER=",
            vm.toString(deployer),
            "\n",
            "CHAIN_ID=",
            vm.toString(block.chainid),
            "\n"
        );

        vm.writeFile("deployments/fork-v4.env", deployments);
        console2.log("V4 infrastructure deployed to fork");
        console2.log("Deployment info saved to: deployments/fork-v4.env");
    }
}
