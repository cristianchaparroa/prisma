// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Universal Router interface
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

// Commands for Universal Router
library Commands {
    uint256 constant V4_SWAP = 0x10;
}

// V4 swap actions (corrected from UniversalRouter source)
library Actions {
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 constant SETTLE_ALL = 0x0c;
    uint256 constant TAKE_ALL = 0x0f;
}

// V4Router ExactInputSingleParams struct
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

/**
 * Simulation - Production V4 Swaps using UniversalRouter with Hook Monitoring
 */
contract Simulation is Script {

    struct SwapConfig {
        address account;
        uint256 privateKey;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        string description;
    }

    // Add this to monitor hook execution
    event HookExecutionCheck(address indexed hook, bool executed, string phase);

    function run() external {
        address universalRouterAddr = vm.envAddress("UNIVERSAL_ROUTER");
        address permit2Addr = vm.envAddress("PERMIT2");
        address tokenUSDC = vm.envAddress("TOKEN_USDC");
        address tokenDAI = vm.envAddress("TOKEN_DAI");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");

        console2.log("Production V4 Swaps using UniversalRouter");
        console2.log("Hook Address:", hookAddr);
        console2.log("UniversalRouter:", universalRouterAddr);

        SwapConfig[] memory swaps = new SwapConfig[](4);

        swaps[0] = SwapConfig({
            account: vm.envAddress("ACCOUNT_1_ADDRESS"),
            privateKey: vm.envUint("ACCOUNT_1_PRIVATE_KEY"),
            tokenIn: tokenUSDC,
            tokenOut: tokenDAI,
            amountIn: 500e6,
            description: "Account 1: USDC -> DAI"
        });

        swaps[1] = SwapConfig({
            account: vm.envAddress("ACCOUNT_2_ADDRESS"),
            privateKey: vm.envUint("ACCOUNT_2_PRIVATE_KEY"),
            tokenIn: tokenDAI,
            tokenOut: tokenUSDC,
            amountIn: 300e18,
            description: "Account 2: DAI -> USDC"
        });

        swaps[2] = SwapConfig({
            account: vm.envAddress("ACCOUNT_3_ADDRESS"),
            privateKey: vm.envUint("ACCOUNT_3_PRIVATE_KEY"),
            tokenIn: tokenUSDC,
            tokenOut: tokenDAI,
            amountIn: 750e6,
            description: "Account 3: USDC -> DAI"
        });

        swaps[3] = SwapConfig({
            account: vm.envAddress("ACCOUNT_4_ADDRESS"),
            privateKey: vm.envUint("ACCOUNT_4_PRIVATE_KEY"),
            tokenIn: tokenDAI,
            tokenOut: tokenUSDC,
            amountIn: 400e18,
            description: "Account 4: DAI -> USDC"
        });

        uint256 startBlock = block.number;
        console2.log("Starting block: %s", vm.toString(startBlock));

        for (uint i = 0; i < swaps.length; i++) {
            _executeSwap(swaps[i], universalRouterAddr, permit2Addr, hookAddr, i);
        }

        console2.log("");
        console2.log("V4 swaps completed!");
        console2.log("Check hook events: cast logs --address %s --from-block %s", hookAddr, vm.toString(startBlock));

        // Additional detailed logging commands
        console2.log("");
        console2.log("=== HOOK VERIFICATION COMMANDS ===");
        console2.log("1. Check all events from hook:");
        console2.log("   cast logs --address", hookAddr, "--from-block", startBlock);
        console2.log("");
        console2.log("2. Check specific hook functions (if your hook emits these):");
        console2.log("   cast logs --address %s --from-block %s", hookAddr, vm.toString(startBlock));
        console2.log("   cast logs --address %s --from-block %s <event_signature>", hookAddr, vm.toString(startBlock));
        console2.log("");
        console2.log("3. Check all logs from the transaction range:");
        console2.log("   cast logs --from-block %s --to-block latest", vm.toString(startBlock));
    }

    function _executeSwap(
        SwapConfig memory config,
        address universalRouterAddr,
        address permit2Addr,
        address hookAddr,
        uint256 swapIndex
    ) internal {
        console2.log("Executing:", config.description);

        vm.startBroadcast(config.privateKey);

        // Store block number before swap for hook verification
        uint256 blockBefore = block.number;

        // Permit2 approvals
        IERC20(config.tokenIn).approve(permit2Addr, config.amountIn * 2);
        IAllowanceTransfer(permit2Addr).approve(
            config.tokenIn,
            universalRouterAddr,
            uint160(config.amountIn * 2),
            uint48(block.timestamp + 3600)
        );

        uint256 balanceInBefore = IERC20(config.tokenIn).balanceOf(config.account);
        uint256 balanceOutBefore = IERC20(config.tokenOut).balanceOf(config.account);
        console2.log("Before - In:", balanceInBefore, "Out:", balanceOutBefore);

        // Build swap using official documentation pattern
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Create PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(config.tokenIn < config.tokenOut ? config.tokenIn : config.tokenOut),
            currency1: Currency.wrap(config.tokenIn < config.tokenOut ? config.tokenOut : config.tokenIn),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

        bool zeroForOne = config.tokenIn == Currency.unwrap(poolKey.currency0);

        // Parameters for each action
        bytes[] memory params = new bytes[](3);

        // SWAP_EXACT_IN_SINGLE params
        params[0] = abi.encode(
            ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(config.amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );

        // SETTLE_ALL params
        params[1] = abi.encode(
            zeroForOne ? poolKey.currency0 : poolKey.currency1,
            config.amountIn
        );

        // TAKE_ALL params
        params[2] = abi.encode(
            zeroForOne ? poolKey.currency1 : poolKey.currency0,
            uint256(0) // take all available
        );

        inputs[0] = abi.encode(actions, params);

        try IUniversalRouter(universalRouterAddr).execute(commands, inputs, block.timestamp + 3600) {
            uint256 balanceInAfter = IERC20(config.tokenIn).balanceOf(config.account);
            uint256 balanceOutAfter = IERC20(config.tokenOut).balanceOf(config.account);

            console2.log("After - In:", balanceInAfter, "Out:", balanceOutAfter);
            console2.log("SUCCESS: Hook events should be emitted!");

            // Show how to verify hook execution for this specific swap
            uint256 blockAfter = block.number;
            console2.log("Swap %s executed in blocks %s to %s", vm.toString(swapIndex + 1), vm.toString(blockBefore), vm.toString(blockAfter));
            console2.log("Check this swap's hook events:");
            console2.log("  cast logs --address %s --from-block %s --to-block %s", hookAddr, vm.toString(blockBefore), vm.toString(blockAfter));

        } catch Error(string memory reason) {
            console2.log("FAILED:", reason);
        }

        vm.stopBroadcast();
        console2.log("---");
    }
}
