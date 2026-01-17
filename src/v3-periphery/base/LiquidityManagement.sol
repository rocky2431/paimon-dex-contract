// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPaimonV3Pool} from "../../v3-interfaces/IPaimonV3Pool.sol";
import {IPaimonV3MintCallback} from "../../v3-interfaces/callback/IPaimonV3MintCallback.sol";
import {TickMath} from "../../v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {CallbackValidation} from "../libraries/CallbackValidation.sol";
import {PeripheryPayments} from "./PeripheryPayments.sol";
import {PeripheryImmutableState} from "./PeripheryImmutableState.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Paimon V3
abstract contract LiquidityManagement is IPaimonV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    error PriceSlippageCheck();
    error PoolNotInitialized();

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IPaimonV3MintCallback
    function paimonV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IPaimonV3Pool pool
        )
    {
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(params.token0, params.token1, params.fee);

        pool = IPaimonV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            if (sqrtPriceX96 == 0) revert PoolNotInitialized();

            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert PriceSlippageCheck();
    }
}
