// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {YieldMaximizerHook} from "../../src/YieldMaximizerHook.sol";

/**
 * @title Deploy Yield Maximizer Hook
 */
contract DeployHook is Script {
    // Core contracts
    IPoolManager public poolManager;
    YieldMaximizerHook public hook;

    // Hook permissions configuration
    uint160 public constant PERMISSIONS = uint160(Hooks.AFTER_INITIALIZE_FLAG) | uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        | uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG) | uint160(Hooks.AFTER_SWAP_FLAG);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Yield Maximizer Hook...");

        // Load PoolManager
        _loadPoolManager();

        // Deploy hook to proper address
        _deployHook();

        // Verify hook deployment
        _verifyHook();

        console.log("\n=== YIELD MAXIMIZER HOOK DEPLOYED ===");
        console.log("Hook address:", address(hook));
        console.log("Permissions:", PERMISSIONS);
        console.log("Ready for pool integration!");

        vm.stopBroadcast();

        // Save hook information
        _saveHookInfo();
    }

    function _loadPoolManager() internal {
        console.log("Loading PoolManager from environment...");

        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        console.log("PoolManager loaded:", address(poolManager));
    }

    function _deployHook() internal {
        console.log("Deploying hook with proper permissions...");

        // Define hook flags for permissions
        uint160 flags = PERMISSIONS;

        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(poolManager);

        console.log("Mining hook address with flags:", flags);

        // Use HookMiner to find a valid address and salt
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY, // Use the standard CREATE2 factory
            flags,
            type(YieldMaximizerHook).creationCode,
            constructorArgs
        );

        console.log("Mined hook address:", hookAddress);
        console.log("Using salt:", vm.toString(salt));

        // Deploy the hook using CREATE2 with the mined salt
        hook = new YieldMaximizerHook{salt: salt}(poolManager);

        console.log("Hook deployed at:", address(hook));

        // Verify the deployed address matches the mined address
        require(address(hook) == hookAddress, "DeployHook: Address Mismatch");

        // Verify the hook address has the required permission bits
        require(_validateHookAddress(address(hook)), "Hook address does not have proper permissions");
        console.log("Hook address validation successful!");
    }

    function _validateHookAddress(address hookAddress) internal pure returns (bool) {
        uint160 addr = uint160(hookAddress);

        // Check if address has the required permission flags
        // Uniswap V4 encodes permissions in the address itself
        bool hasAfterInitialize = (addr & Hooks.AFTER_INITIALIZE_FLAG) != 0;
        bool hasAfterAddLiquidity = (addr & Hooks.AFTER_ADD_LIQUIDITY_FLAG) != 0;
        bool hasAfterRemoveLiquidity = (addr & Hooks.AFTER_REMOVE_LIQUIDITY_FLAG) != 0;
        bool hasAfterSwap = (addr & Hooks.AFTER_SWAP_FLAG) != 0;

        return hasAfterInitialize && hasAfterAddLiquidity && hasAfterRemoveLiquidity && hasAfterSwap;
    }

    function _verifyHook() internal view {
        console.log("Verifying hook deployment...");

        // Verify the hook contract exists
        require(address(hook).code.length > 0, "Hook not deployed");

        // Verify hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();

        require(permissions.afterInitialize, "Missing afterInitialize permission");
        require(permissions.afterAddLiquidity, "Missing afterAddLiquidity permission");
        require(permissions.afterRemoveLiquidity, "Missing afterRemoveLiquidity permission");
        require(permissions.afterSwap, "Missing afterSwap permission");

        console.log("Hook permissions verified:");
        console.log("  afterInitialize:", permissions.afterInitialize);
        console.log("  afterAddLiquidity:", permissions.afterAddLiquidity);
        console.log("  afterRemoveLiquidity:", permissions.afterRemoveLiquidity);
        console.log("  afterSwap:", permissions.afterSwap);

        // Verify hook points to correct PoolManager
        // Note: This would require a getter function in the hook contract
        console.log("Hook verification complete");
    }

    function _saveHookInfo() internal {
        console.log("Saving hook deployment information...");

        string memory hookInfo = "# Yield Maximizer Hook Deployment\n";
        hookInfo = string.concat(hookInfo, "HOOK_ADDRESS=", vm.toString(address(hook)), "\n");
        hookInfo = string.concat(hookInfo, "POOL_MANAGER=", vm.toString(address(poolManager)), "\n");
        hookInfo = string.concat(hookInfo, "PERMISSIONS=", vm.toString(PERMISSIONS), "\n");
        hookInfo = string.concat(hookInfo, "DEPLOYER=", vm.toString(vm.addr(vm.envUint("ANVIL_PRIVATE_KEY"))), "\n");
        hookInfo = string.concat(hookInfo, "DEPLOYMENT_BLOCK=", vm.toString(block.number), "\n");
        hookInfo = string.concat(hookInfo, "DEPLOYMENT_TIMESTAMP=", vm.toString(block.timestamp), "\n");

        // Add permission details
        hookInfo = string.concat(hookInfo, "\n# Permission Flags\n");
        hookInfo = string.concat(hookInfo, "AFTER_INITIALIZE=true\n");
        hookInfo = string.concat(hookInfo, "AFTER_ADD_LIQUIDITY=true\n");
        hookInfo = string.concat(hookInfo, "AFTER_REMOVE_LIQUIDITY=true\n");
        hookInfo = string.concat(hookInfo, "AFTER_SWAP=true\n");

        vm.writeFile("./deployments/hook.env", hookInfo);
        console.log("Hook info saved to: ./deployments/hook.env");
    }

    // Helper functions for testing
    function getHookAddress() external view returns (address) {
        return address(hook);
    }

    function getPoolManager() external view returns (address) {
        return address(poolManager);
    }

    function getPermissions() external pure returns (uint160) {
        return PERMISSIONS;
    }

    function validateDeployment() external view returns (bool) {
        if (address(hook) == address(0)) return false;
        if (address(hook).code.length == 0) return false;

        // Verify permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        return permissions.afterInitialize && permissions.afterAddLiquidity && permissions.afterRemoveLiquidity
            && permissions.afterSwap;
    }
}
