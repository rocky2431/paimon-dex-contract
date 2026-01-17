// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "../../../src/v3-core/libraries/TickMath.sol";

contract TickMathWrapper {
    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick);
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}

contract TickMathTest is Test {
    TickMathWrapper public wrapper;

    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;
    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function setUp() public {
        wrapper = new TickMathWrapper();
    }

    // getSqrtRatioAtTick tests

    function test_getSqrtRatioAtTick_RevertOnTickTooLow() public {
        vm.expectRevert(TickMath.TickOutOfBounds.selector);
        wrapper.getSqrtRatioAtTick(MIN_TICK - 1);
    }

    function test_getSqrtRatioAtTick_RevertOnTickTooHigh() public {
        vm.expectRevert(TickMath.TickOutOfBounds.selector);
        wrapper.getSqrtRatioAtTick(MAX_TICK + 1);
    }

    function test_getSqrtRatioAtTick_MinTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(MIN_TICK);
        assertEq(sqrtRatio, MIN_SQRT_RATIO);
    }

    function test_getSqrtRatioAtTick_MaxTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(MAX_TICK);
        assertEq(sqrtRatio, MAX_SQRT_RATIO);
    }

    function test_getSqrtRatioAtTick_ZeroTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(0);
        // At tick 0, price is 1, so sqrtPrice = 1 * 2^96
        assertEq(sqrtRatio, 79228162514264337593543950336);
    }

    function test_getSqrtRatioAtTick_PositiveTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(1);
        // Should be slightly more than tick 0
        assertGt(sqrtRatio, wrapper.getSqrtRatioAtTick(0));
    }

    function test_getSqrtRatioAtTick_NegativeTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(-1);
        // Should be slightly less than tick 0
        assertLt(sqrtRatio, wrapper.getSqrtRatioAtTick(0));
    }

    // getTickAtSqrtRatio tests

    function test_getTickAtSqrtRatio_RevertOnPriceTooLow() public {
        vm.expectRevert(TickMath.SqrtPriceOutOfBounds.selector);
        wrapper.getTickAtSqrtRatio(MIN_SQRT_RATIO - 1);
    }

    function test_getTickAtSqrtRatio_RevertOnPriceTooHigh() public {
        vm.expectRevert(TickMath.SqrtPriceOutOfBounds.selector);
        wrapper.getTickAtSqrtRatio(MAX_SQRT_RATIO);
    }

    function test_getTickAtSqrtRatio_MinSqrtRatio() public view {
        int24 tick = wrapper.getTickAtSqrtRatio(MIN_SQRT_RATIO);
        assertEq(tick, MIN_TICK);
    }

    function test_getTickAtSqrtRatio_MaxSqrtRatioMinus1() public view {
        int24 tick = wrapper.getTickAtSqrtRatio(MAX_SQRT_RATIO - 1);
        assertEq(tick, MAX_TICK - 1);
    }

    function test_getTickAtSqrtRatio_AtTick0() public view {
        int24 tick = wrapper.getTickAtSqrtRatio(79228162514264337593543950336);
        assertEq(tick, 0);
    }

    // Roundtrip tests

    function test_Roundtrip_TickZero() public view {
        int24 tick = 0;
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(tick);
        int24 resultTick = wrapper.getTickAtSqrtRatio(sqrtRatio);
        assertEq(resultTick, tick);
    }

    function test_Roundtrip_MinTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(MIN_TICK);
        int24 resultTick = wrapper.getTickAtSqrtRatio(sqrtRatio);
        assertEq(resultTick, MIN_TICK);
    }

    function test_Roundtrip_MaxTick() public view {
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(MAX_TICK);
        int24 resultTick = wrapper.getTickAtSqrtRatio(sqrtRatio - 1);
        assertEq(resultTick, MAX_TICK - 1);
    }

    // Fuzz tests

    function testFuzz_getSqrtRatioAtTick_ValidRange(int24 tick) public view {
        vm.assume(tick >= MIN_TICK && tick <= MAX_TICK);
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(tick);

        // Result should be within valid range
        assertTrue(sqrtRatio >= MIN_SQRT_RATIO);
        assertTrue(sqrtRatio <= MAX_SQRT_RATIO);
    }

    function testFuzz_getTickAtSqrtRatio_ValidRange(uint160 sqrtRatio) public view {
        vm.assume(sqrtRatio >= MIN_SQRT_RATIO && sqrtRatio < MAX_SQRT_RATIO);
        int24 tick = wrapper.getTickAtSqrtRatio(sqrtRatio);

        // Result should be within valid range
        assertTrue(tick >= MIN_TICK);
        assertTrue(tick <= MAX_TICK);
    }

    function testFuzz_Roundtrip_Consistency(int24 tick) public view {
        vm.assume(tick >= MIN_TICK && tick <= MAX_TICK);
        uint160 sqrtRatio = wrapper.getSqrtRatioAtTick(tick);

        if (sqrtRatio < MAX_SQRT_RATIO) {
            int24 resultTick = wrapper.getTickAtSqrtRatio(sqrtRatio);
            // Due to rounding, result tick should be equal to original tick
            assertEq(resultTick, tick);
        }
    }
}
