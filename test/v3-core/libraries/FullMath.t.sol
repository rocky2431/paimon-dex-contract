// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FullMath} from "../../../src/v3-core/libraries/FullMath.sol";

// Wrapper contract to test internal library functions
contract FullMathWrapper {
    function mulDiv(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return FullMath.mulDivRoundingUp(a, b, denominator);
    }
}

contract FullMathTest is Test {
    FullMathWrapper public wrapper;

    function setUp() public {
        wrapper = new FullMathWrapper();
    }

    // mulDiv tests

    function test_MulDiv_RevertOnZeroDenominator() public {
        vm.expectRevert();
        wrapper.mulDiv(1, 1, 0);
    }

    function test_MulDiv_RevertOnOverflow() public {
        vm.expectRevert();
        wrapper.mulDiv(type(uint256).max, type(uint256).max, 1);
    }

    function test_MulDiv_RevertOnOverflowDenominator() public {
        vm.expectRevert();
        wrapper.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max - 1);
    }

    function test_MulDiv_AllMaxInputs() public view {
        uint256 result = wrapper.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(result, type(uint256).max);
    }

    function test_MulDiv_AccuratePrecision() public view {
        uint256 result = wrapper.mulDiv(
            type(uint256).max,
            type(uint256).max - 1,
            type(uint256).max
        );
        assertEq(result, type(uint256).max - 1);
    }

    function test_MulDiv_SimpleCase() public view {
        assertEq(wrapper.mulDiv(100, 200, 50), 400);
    }

    function test_MulDiv_PhantomOverflow() public view {
        // This would overflow in naive a*b/c
        uint256 a = 1 << 200;
        uint256 b = 1 << 100;
        uint256 c = 1 << 50;
        uint256 result = wrapper.mulDiv(a, b, c);
        assertEq(result, 1 << 250);
    }

    function test_MulDiv_KnownValue() public view {
        assertEq(wrapper.mulDiv(1e27, 1e27, 1e18), 1e36);
    }

    // mulDivRoundingUp tests

    function test_MulDivRoundingUp_RevertOnZeroDenominator() public {
        vm.expectRevert();
        wrapper.mulDivRoundingUp(1, 1, 0);
    }

    function test_MulDivRoundingUp_RevertOnOverflow() public {
        vm.expectRevert();
        wrapper.mulDivRoundingUp(type(uint256).max, type(uint256).max, 1);
    }

    function test_MulDivRoundingUp_RoundsUp() public view {
        assertEq(wrapper.mulDivRoundingUp(5, 3, 2), 8); // 15/2 = 7.5 -> 8
    }

    function test_MulDivRoundingUp_NoRoundNeeded() public view {
        assertEq(wrapper.mulDivRoundingUp(4, 3, 2), 6); // 12/2 = 6
    }

    function test_MulDivRoundingUp_MaxResult() public view {
        // max * max / max = max, no need to round up
        uint256 result = wrapper.mulDivRoundingUp(type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(result, type(uint256).max);
    }

    // Fuzz tests

    function testFuzz_MulDiv_IdentityDenominator(uint256 a, uint256 b) public view {
        vm.assume(a > 0);
        vm.assume(b <= type(uint256).max / a);

        assertEq(wrapper.mulDiv(a, b, 1), a * b);
    }

    function testFuzz_MulDiv_IdentityMultiplier(uint256 a, uint256 denom) public view {
        vm.assume(denom > 0);

        assertEq(wrapper.mulDiv(a, 1, denom), a / denom);
    }
}
