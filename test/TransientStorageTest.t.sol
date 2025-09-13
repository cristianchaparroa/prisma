// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";

contract TransientStorageTest is Test {
    
    function testTransientStorage() public {
        console2.log("Testing transient storage support in Foundry...");
        
        // Test the exact pattern V4 uses
        bytes32 constant SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        
        // Store value using tstore
        assembly ("memory-safe") {
            tstore(SLOT, true)
        }
        
        // Read value using tload
        bool result;
        assembly ("memory-safe") {
            result := tload(SLOT)
        }
        
        console2.log("Transient storage result:", result);
        assertTrue(result, "Transient storage should return true");
        
        console2.log("SUCCESS: Foundry supports transient storage!");
    }
    
    function testV4LockPattern() public {
        console2.log("Testing V4 Lock pattern...");
        
        // Simulate V4's lock/unlock pattern
        _unlock();
        assertTrue(_isUnlocked(), "Should be unlocked");
        
        _lock();
        assertFalse(_isUnlocked(), "Should be locked");
        
        console2.log("SUCCESS: V4 Lock pattern works in Foundry!");
    }
    
    function _unlock() internal {
        bytes32 constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }
    
    function _lock() internal {
        bytes32 constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, false)
        }
    }
    
    function _isUnlocked() internal view returns (bool unlocked) {
        bytes32 constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;
        assembly ("memory-safe") {
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}