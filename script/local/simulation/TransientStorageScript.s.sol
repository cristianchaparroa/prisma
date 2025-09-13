// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

contract TransientStorageScript is Script {
    
    function run() public {
        console2.log("=== Testing Transient Storage in Foundry Script ===");
        
        // Test the exact pattern V4 uses
        bytes32 SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        
        console2.log("Step 1: Testing basic tstore/tload...");
        
        // Store value using tstore
        assembly ("memory-safe") {
            tstore(SLOT, 0x42)
        }
        
        // Read value using tload
        uint256 result;
        assembly ("memory-safe") {
            result := tload(SLOT)
        }
        
        console2.log("Stored: 0x42, Retrieved:", result);
        
        if (result == 0x42) {
            console2.log("SUCCESS: Transient storage works in scripts!");
        } else {
            console2.log("FAILED: Transient storage doesn't work in scripts");
            return;
        }
        
        console2.log("\nStep 2: Testing V4 unlock pattern...");
        
        // Test V4's unlock pattern
        _testUnlockPattern();
        
        console2.log("=== Transient Storage Test Complete ===");
    }
    
    function _testUnlockPattern() internal {
        bytes32 IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        
        // Initially should be locked (false/0)
        bool initial = _isUnlocked();
        console2.log("Initial lock state:", initial);
        
        // Unlock
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, 1)
        }
        
        bool afterUnlock = _isUnlocked();
        console2.log("After unlock:", afterUnlock);
        
        // Lock again
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, 0)
        }
        
        bool afterLock = _isUnlocked();
        console2.log("After lock:", afterLock);
        
        if (!initial && afterUnlock && !afterLock) {
            console2.log("SUCCESS: V4 lock/unlock pattern works in scripts!");
        } else {
            console2.log("FAILED: V4 lock/unlock pattern issue in scripts");
        }
    }
    
    function _isUnlocked() internal view returns (bool unlocked) {
        bytes32 IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        assembly ("memory-safe") {
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}