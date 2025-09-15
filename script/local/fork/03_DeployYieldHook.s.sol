// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {YieldMaximizerHook} from "../../../src/YieldMaximizerHook.sol";

contract DeployYieldHook is Script {
    // Hook permissions configuration
    uint160 public constant PERMISSIONS = uint160(Hooks.AFTER_INITIALIZE_FLAG)
    | uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)
    | uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
    | uint160(Hooks.AFTER_SWAP_FLAG);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Deploying Yield Maximizer Hook...");
        console2.log("PoolManager:", address(poolManager));

        uint160 flags = PERMISSIONS;
        bytes memory constructorArgs = abi.encode(poolManager);

        console2.log("Mining hook address with flags:", flags);

        (address hookAddress, bytes32 salt) =
                            HookMiner.find(CREATE2_FACTORY, flags, type(YieldMaximizerHook).creationCode, constructorArgs);

        console2.log("Mined hook address:", hookAddress);
        console2.log("Using salt:", vm.toString(salt));

        YieldMaximizerHook hook = new YieldMaximizerHook{salt: salt}(poolManager);

        console2.log("Hook deployed at:", address(hook));

        require(address(hook) == hookAddress, "Address Mismatch");
        require(_validateHookAddress(address(hook)), "Hook address does not have proper permissions");
        console2.log("Hook address validation successful");

        vm.stopBroadcast();

        vm.writeFile("deployments/fork-hook.env", string.concat("HOOK_ADDRESS=", vm.toString(address(hook)), "\n"));
        console2.log("YieldMaximizerHook deployed and verified");
    }

    function _validateHookAddress(address hookAddress) internal pure returns (bool) {
        uint160 addr = uint160(hookAddress);

        bool hasAfterInitialize = (addr & Hooks.AFTER_INITIALIZE_FLAG) != 0;
        bool hasAfterAddLiquidity = (addr & Hooks.AFTER_ADD_LIQUIDITY_FLAG) != 0;
        bool hasAfterRemoveLiquidity = (addr & Hooks.AFTER_REMOVE_LIQUIDITY_FLAG) != 0;
        bool hasAfterSwap = (addr & Hooks.AFTER_SWAP_FLAG) != 0;

        return hasAfterInitialize && hasAfterAddLiquidity && hasAfterRemoveLiquidity && hasAfterSwap;
    }
}
