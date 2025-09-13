// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";

contract MinimalUnlockTest is Script, IUnlockCallback {
    IPoolManager public poolManager;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        
        console2.log("=== MINIMAL UNLOCK TEST ===");
        console2.log("PoolManager:", address(poolManager));
        
        vm.startBroadcast(deployerPrivateKey);
        
        console2.log("Calling unlock with minimal callback...");
        
        try poolManager.unlock("test") returns (bytes memory result) {
            console2.log("SUCCESS: unlock/callback pattern works!");
            console2.logBytes(result);
        } catch Error(string memory reason) {
            console2.log("FAILED: unlock/callback error:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("FAILED: unlock/callback low level error");
            console2.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
    
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        console2.log("unlockCallback called successfully!");
        console2.log("Data length:", data.length);
        if (data.length > 0) {
            console2.logBytes(data);
        }
        
        // Return success
        return "success";
    }
}