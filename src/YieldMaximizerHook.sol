// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract YieldMaximizerHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    event UserRemovedFromPool(address indexed user, PoolId indexed poolId);

    // Debug Events
    event DebugEvent(string message);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, /* sender */ PoolKey calldata key, uint160, /* sqrtPriceX96 */ int24 /* tick */ )
        internal
        override
        returns (bytes4)
    {
        emit DebugEvent("_afterInitialize");
        return BaseHook.afterInitialize.selector;
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        emit DebugEvent("_afterSwap");
        return (BaseHook.afterSwap.selector, 0);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata, /* modifyParams */
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        emit DebugEvent("_afterAddLiquidity");
        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata, /* modifyParams */
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        emit DebugEvent("_afterRemoveLiquidity");
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }
}
