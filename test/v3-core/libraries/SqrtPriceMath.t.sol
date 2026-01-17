// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SqrtPriceMath} from "../../../src/v3-core/libraries/SqrtPriceMath.sol";
import {FixedPoint96} from "../../../src/v3-core/libraries/FixedPoint96.sol";

contract SqrtPriceMathWrapper {
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) external pure returns (uint160) {
        return SqrtPriceMath.getNextSqrtPriceFromInput(sqrtPX96, liquidity, amountIn, zeroForOne);
    }

    function getNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) external pure returns (uint160) {
        return SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPX96, liquidity, amountOut, zeroForOne);
    }

    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) external pure returns (uint256) {
        return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    }

    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) external pure returns (uint256) {
        return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    }

    function getAmount0DeltaSigned(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) external pure returns (int256) {
        return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function getAmount1DeltaSigned(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) external pure returns (int256) {
        return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}

contract SqrtPriceMathTest is Test {
    SqrtPriceMathWrapper public wrapper;

    // Common test values
    uint160 constant PRICE_1_TO_1 = 79228162514264337593543950336; // sqrt(1) * 2^96
    uint128 constant LIQUIDITY = 1e18;

    function setUp() public {
        wrapper = new SqrtPriceMathWrapper();
    }

    // getNextSqrtPriceFromInput tests

    function test_getNextSqrtPriceFromInput_RevertOnZeroPrice() public {
        vm.expectRevert(SqrtPriceMath.InvalidPrice.selector);
        wrapper.getNextSqrtPriceFromInput(0, LIQUIDITY, 1e18, true);
    }

    function test_getNextSqrtPriceFromInput_RevertOnZeroLiquidity() public {
        vm.expectRevert(SqrtPriceMath.NotEnoughLiquidity.selector);
        wrapper.getNextSqrtPriceFromInput(PRICE_1_TO_1, 0, 1e18, true);
    }

    function test_getNextSqrtPriceFromInput_ZeroAmount() public view {
        uint160 result = wrapper.getNextSqrtPriceFromInput(PRICE_1_TO_1, LIQUIDITY, 0, true);
        assertEq(result, PRICE_1_TO_1);
    }

    function test_getNextSqrtPriceFromInput_Token0In_PriceDecreases() public view {
        uint160 result = wrapper.getNextSqrtPriceFromInput(PRICE_1_TO_1, LIQUIDITY, 1e18, true);
        // When adding token0, price should decrease
        assertLt(result, PRICE_1_TO_1);
    }

    function test_getNextSqrtPriceFromInput_Token1In_PriceIncreases() public view {
        uint160 result = wrapper.getNextSqrtPriceFromInput(PRICE_1_TO_1, LIQUIDITY, 1e18, false);
        // When adding token1, price should increase
        assertGt(result, PRICE_1_TO_1);
    }

    // getNextSqrtPriceFromOutput tests

    function test_getNextSqrtPriceFromOutput_RevertOnZeroPrice() public {
        vm.expectRevert(SqrtPriceMath.InvalidPrice.selector);
        wrapper.getNextSqrtPriceFromOutput(0, LIQUIDITY, 1e18, true);
    }

    function test_getNextSqrtPriceFromOutput_RevertOnZeroLiquidity() public {
        vm.expectRevert(SqrtPriceMath.NotEnoughLiquidity.selector);
        wrapper.getNextSqrtPriceFromOutput(PRICE_1_TO_1, 0, 1e18, true);
    }

    function test_getNextSqrtPriceFromOutput_Token1Out_PriceDecreases() public view {
        uint160 result = wrapper.getNextSqrtPriceFromOutput(PRICE_1_TO_1, LIQUIDITY, 1e15, true);
        // When removing token1, price should decrease
        assertLt(result, PRICE_1_TO_1);
    }

    function test_getNextSqrtPriceFromOutput_Token0Out_PriceIncreases() public view {
        uint160 result = wrapper.getNextSqrtPriceFromOutput(PRICE_1_TO_1, LIQUIDITY, 1e15, false);
        // When removing token0, price should increase
        assertGt(result, PRICE_1_TO_1);
    }

    // getAmount0Delta tests

    function test_getAmount0Delta_SamePrices() public view {
        uint256 result = wrapper.getAmount0Delta(PRICE_1_TO_1, PRICE_1_TO_1, LIQUIDITY, true);
        assertEq(result, 0);
    }

    function test_getAmount0Delta_Symmetric() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        uint256 result1 = wrapper.getAmount0Delta(priceA, priceB, LIQUIDITY, true);
        uint256 result2 = wrapper.getAmount0Delta(priceB, priceA, LIQUIDITY, true);

        assertEq(result1, result2);
    }

    function test_getAmount0Delta_RoundingUp() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 + 1000;

        uint256 roundUp = wrapper.getAmount0Delta(priceA, priceB, LIQUIDITY, true);
        uint256 roundDown = wrapper.getAmount0Delta(priceA, priceB, LIQUIDITY, false);

        assertTrue(roundUp >= roundDown);
    }

    // getAmount1Delta tests

    function test_getAmount1Delta_SamePrices() public view {
        uint256 result = wrapper.getAmount1Delta(PRICE_1_TO_1, PRICE_1_TO_1, LIQUIDITY, true);
        assertEq(result, 0);
    }

    function test_getAmount1Delta_Symmetric() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        uint256 result1 = wrapper.getAmount1Delta(priceA, priceB, LIQUIDITY, true);
        uint256 result2 = wrapper.getAmount1Delta(priceB, priceA, LIQUIDITY, true);

        assertEq(result1, result2);
    }

    function test_getAmount1Delta_RoundingUp() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 + 1000;

        uint256 roundUp = wrapper.getAmount1Delta(priceA, priceB, LIQUIDITY, true);
        uint256 roundDown = wrapper.getAmount1Delta(priceA, priceB, LIQUIDITY, false);

        assertTrue(roundUp >= roundDown);
    }

    // Signed delta tests

    function test_getAmount0DeltaSigned_PositiveLiquidity() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        int256 result = wrapper.getAmount0DeltaSigned(priceA, priceB, int128(int256(uint256(LIQUIDITY))));
        assertTrue(result > 0);
    }

    function test_getAmount0DeltaSigned_NegativeLiquidity() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        int256 result = wrapper.getAmount0DeltaSigned(priceA, priceB, -int128(int256(uint256(LIQUIDITY))));
        assertTrue(result < 0);
    }

    function test_getAmount1DeltaSigned_PositiveLiquidity() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        int256 result = wrapper.getAmount1DeltaSigned(priceA, priceB, int128(int256(uint256(LIQUIDITY))));
        assertTrue(result > 0);
    }

    function test_getAmount1DeltaSigned_NegativeLiquidity() public view {
        uint160 priceA = PRICE_1_TO_1;
        uint160 priceB = PRICE_1_TO_1 * 2;

        int256 result = wrapper.getAmount1DeltaSigned(priceA, priceB, -int128(int256(uint256(LIQUIDITY))));
        assertTrue(result < 0);
    }
}
