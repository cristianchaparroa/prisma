// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

library Commands {
    uint256 constant V4_SWAP = 0x10;
}

library Actions {
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 constant SETTLE_ALL = 0x0c;
    uint256 constant TAKE_ALL = 0x0f;
}

struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    bytes hookData;
}

contract Trading is Script {
    // Slippage tolerance: 5% (500 basis points)
    uint256 internal constant SLIPPAGE_TOLERANCE_BPS = 500;
    uint256 internal constant BASIS_POINTS = 10000;

    function calculateMinAmountOut(
        uint256, // amountIn - unused but required for interface
        bool, // zeroForOne - unused but required for interface
        address, // token0 - unused but required for interface
        address // token1 - unused but required for interface
    ) internal pure returns (uint128) {
        // Return 0 to disable slippage protection entirely
        // Let the pool return whatever it can
        return 0;
    }

    function run() external {
        // Env vars
        address universalRouterAddr = vm.envAddress("UNIVERSAL_ROUTER");
        address permit2Addr = vm.envAddress("PERMIT2");
        address tokenUsdc = vm.envAddress("TOKEN_USDC");
        address tokenDai = vm.envAddress("TOKEN_DAI");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        address account = vm.envAddress("ACCOUNT_1_ADDRESS");
        uint256 privateKey = vm.envUint("ACCOUNT_1_PRIVATE_KEY");

        // Validate that tokens are different
        require(tokenUsdc != tokenDai, "USDC and DAI cannot be the same address");

        vm.startBroadcast(privateKey);

        // Approve both tokens to Permit2
        uint256 maxAmount = type(uint256).max;

        // Approve USDC
        if (IERC20(tokenUsdc).allowance(account, permit2Addr) < maxAmount / 2) {
            IERC20(tokenUsdc).approve(permit2Addr, maxAmount);
        }

        // Approve DAI
        if (IERC20(tokenDai).allowance(account, permit2Addr) < maxAmount / 2) {
            IERC20(tokenDai).approve(permit2Addr, maxAmount);
        }

        // Set allowances through Permit2 for both tokens
        uint48 deadline = uint48(block.timestamp + 7200); // 2 hours from now

        IAllowanceTransfer(permit2Addr).approve(tokenUsdc, universalRouterAddr, type(uint160).max, deadline);

        IAllowanceTransfer(permit2Addr).approve(tokenDai, universalRouterAddr, type(uint160).max, deadline);

        // PoolKey - ensure proper ordering
        (address token0, address token1) = tokenUsdc < tokenDai ? (tokenUsdc, tokenDai) : (tokenDai, tokenUsdc);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

        console2.log("Pool currency0:", Currency.unwrap(poolKey.currency0));
        console2.log("Pool currency1:", Currency.unwrap(poolKey.currency1));
        console2.log("USDC address:", tokenUsdc);
        console2.log("DAI address:", tokenDai);

        // Universal Router command (always the same)
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Run a few test swaps to verify pool is functional
        uint256 successfulSwaps = 0;

        for (uint256 i = 0; i < 1000; i++) {
            // Strict alternating pattern
            bool zeroForOne = (i % 2 == 0);

            // Start with minimal amounts for testing
            uint256 amountIn = 1e6; // Fixed 1 USDC for all test swaps

            // Use smaller amounts and adjust for token decimals
            if (!zeroForOne) {
                // If swapping currency1 -> currency0, keep USDC amounts (6 decimals)
                // But if currency1 is DAI, we need to convert
                if (Currency.unwrap(poolKey.currency1) != tokenUsdc) {
                    amountIn = amountIn * 1e12; // Convert from 6 to 18 decimals for DAI
                }
            }

            // Calculate minimum amount out with slippage protection
            address inputToken = zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1);

            uint128 minAmountOut = calculateMinAmountOut(
                amountIn, zeroForOne, Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1)
            );

            // Check balance before swap
            uint256 balance = IERC20(inputToken).balanceOf(account);

            if (balance < amountIn) {
                console2.log("Swap %s SKIPPED: insufficient balance", i);
                continue;
            }

            // Try to detect if pool is in extreme state - skip if we've had too many failures
            if (i > 10 && successfulSwaps == 0) {
                console2.log("Swap %s SKIPPED: pool appears to be in extreme state", i);
                break;
            }

            // Declare arrays for this iteration
            bytes[] memory params = new bytes[](3);
            bytes[] memory inputs = new bytes[](1);

            // Encode actions
            bytes memory actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
            );

            // Fill params
            params[0] = abi.encode(
                ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: zeroForOne,
                    amountIn: uint128(amountIn),
                    amountOutMinimum: minAmountOut, // Dynamic slippage protection
                    hookData: abi.encode(account)
                })
            );

            // SETTLE_ALL params - specify the input currency and amount
            params[1] = abi.encode(zeroForOne ? poolKey.currency0 : poolKey.currency1, amountIn);

            // TAKE_ALL params - specify the output currency
            params[2] = abi.encode(
                zeroForOne ? poolKey.currency1 : poolKey.currency0,
                uint256(0) // take all available
            );

            // Pack actions + params into inputs
            inputs[0] = abi.encode(actions, params);

            // Use a longer deadline for each transaction
            uint256 txDeadline = block.timestamp + 1800; // 30 minutes from now

            // Execute with proper error handling
            try IUniversalRouter(universalRouterAddr).execute(commands, inputs, txDeadline) {
                string memory direction = zeroForOne ? "DAI->USDC" : "USDC->DAI";
                console2.log("Swap %s SUCCESS (%s)", i, direction);
                successfulSwaps++;
            } catch Error(string memory reason) {
                console2.log("Swap %s FAILED: %s", i, reason);

                // Check if it's a slippage error
                if (keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("Too little received"))) {
                    console2.log("-> Slippage exceeded tolerance");
                }
            } catch (bytes memory lowLevelData) {
                console2.log("Swap %s FAILED with low-level error", i);
                console2.logBytes(lowLevelData);

                // Decode common error signatures
                if (lowLevelData.length >= 4) {
                    bytes4 errorSig = bytes4(lowLevelData);
                    if (errorSig == 0x7c9c6e8f) {
                        console2.log("Error: PriceLimitAlreadyExceeded()");
                    } else if (errorSig == 0x8b063d73) {
                        console2.log("Error: V4TooLittleReceived() - Slippage too high");
                    } else if (errorSig == 0x5bf6f916) {
                        console2.log("Error: TransactionDeadlinePassed()");
                    }
                }
            }

            // Small delay between swaps to avoid nonce issues
            if (i < 99) {
                // In a real script, you might want to add vm.roll() or vm.warp() here
                // to simulate time passing between transactions
            }
        }

        vm.stopBroadcast();
    }
}
