// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SwapMath} from "../../../src/v3-core/libraries/SwapMath.sol";

contract SwapMathWrapper {
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    )
        external
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        return SwapMath.computeSwapStep(
            sqrtRatioCurrentX96,
            sqrtRatioTargetX96,
            liquidity,
            amountRemaining,
            feePips
        );
    }
}

contract SwapMathTest is Test {
    SwapMathWrapper public wrapper;

    // Common test values
    uint160 constant PRICE_1_TO_1 = 79228162514264337593543950336;
    uint160 constant PRICE_HIGHER = 158456325028528675187087900672; // 2x price
    uint160 constant PRICE_LOWER = 39614081257132168796771975168; // 0.5x price
    uint128 constant LIQUIDITY = 1e18;
    uint24 constant FEE_PIPS = 3000; // 0.3%

    function setUp() public {
        wrapper = new SwapMathWrapper();
    }

    // Exact input tests (amountRemaining >= 0)

    function test_ExactInput_ZeroForOne_PartialFill() public view {
        int256 amountRemaining = 1e15; // Small amount, won't reach target

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Price should decrease but not reach target
        assertLt(sqrtRatioNextX96, PRICE_1_TO_1);
        assertGt(sqrtRatioNextX96, PRICE_LOWER);

        // amountIn + feeAmount should equal amountRemaining
        assertEq(amountIn + feeAmount, uint256(amountRemaining));

        // Should have some output
        assertGt(amountOut, 0);
    }

    function test_ExactInput_ZeroForOne_FullFill() public view {
        int256 amountRemaining = 1e21; // Large amount, will reach target

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Price should reach target
        assertEq(sqrtRatioNextX96, PRICE_LOWER);

        // amountIn should be less than amountRemaining (didn't use all)
        assertLt(amountIn + feeAmount, uint256(amountRemaining));
    }

    function test_ExactInput_OneForZero_PartialFill() public view {
        int256 amountRemaining = 1e15;

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_HIGHER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Price should increase but not reach target
        assertGt(sqrtRatioNextX96, PRICE_1_TO_1);
        assertLt(sqrtRatioNextX96, PRICE_HIGHER);

        // amountIn + feeAmount should equal amountRemaining
        assertEq(amountIn + feeAmount, uint256(amountRemaining));
    }

    // Exact output tests (amountRemaining < 0)

    function test_ExactOutput_ZeroForOne_PartialFill() public view {
        int256 amountRemaining = -1e15; // Want some output

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Price should decrease
        assertLt(sqrtRatioNextX96, PRICE_1_TO_1);

        // Should have input and fee
        assertGt(amountIn, 0);
        assertGt(feeAmount, 0);

        // Output should be requested amount or less
        assertLe(amountOut, uint256(-amountRemaining));
    }

    function test_ExactOutput_OneForZero_PartialFill() public view {
        int256 amountRemaining = -1e15;

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_HIGHER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Price should increase
        assertGt(sqrtRatioNextX96, PRICE_1_TO_1);

        // Should have input and fee
        assertGt(amountIn, 0);
        assertGt(feeAmount, 0);
    }

    // Fee tests

    function test_FeeCalculation_ExactInput() public view {
        int256 amountRemaining = 1e18;

        (, uint256 amountIn,, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, FEE_PIPS);

        // Fee should be proportional to amountIn
        // feeAmount ≈ amountIn * feePips / (1e6 - feePips)
        uint256 expectedFeeApprox = amountIn * FEE_PIPS / (1e6 - FEE_PIPS);

        // Allow 1% tolerance due to rounding
        assertApproxEqRel(feeAmount, expectedFeeApprox, 0.01e18);
    }

    function test_ZeroFee() public view {
        int256 amountRemaining = 1e18;

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, 0);

        // With zero fee, feeAmount should be 0
        assertEq(feeAmount, 0);

        // amountIn should equal amountRemaining
        assertEq(amountIn, uint256(amountRemaining));
    }

    function test_HighFee() public view {
        int256 amountRemaining = 1e18;
        uint24 highFee = 100000; // 10%

        (, uint256 amountIn,, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_LOWER, LIQUIDITY, amountRemaining, highFee);

        // Fee should be significant portion
        assertGt(feeAmount, amountIn / 20); // At least 5% of amountIn
    }

    // Edge cases

    function test_SamePrice() public view {
        int256 amountRemaining = 1e18;

        (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            wrapper.computeSwapStep(PRICE_1_TO_1, PRICE_1_TO_1, LIQUIDITY, amountRemaining, FEE_PIPS);

        // When current == target, price stays the same
        assertEq(sqrtRatioNextX96, PRICE_1_TO_1);
        // amountIn is 0 when no price movement
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
        // When we reach target (even if it's same as current), the fee is calculated on amountIn
        // Since amountIn=0, feeAmount = 0 * FEE_PIPS / (1e6 - FEE_PIPS) = 0
        assertEq(feeAmount, 0);
    }
}
