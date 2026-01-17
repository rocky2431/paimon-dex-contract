// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BitMath} from "../../../src/v3-core/libraries/BitMath.sol";

// Wrapper contract to test internal library functions
contract BitMathWrapper {
    function mostSignificantBit(uint256 x) external pure returns (uint8) {
        return BitMath.mostSignificantBit(x);
    }

    function leastSignificantBit(uint256 x) external pure returns (uint8) {
        return BitMath.leastSignificantBit(x);
    }
}

contract BitMathTest is Test {
    BitMathWrapper public wrapper;

    function setUp() public {
        wrapper = new BitMathWrapper();
    }

    // mostSignificantBit tests

    function test_MostSignificantBit_RevertOnZero() public {
        vm.expectRevert();
        wrapper.mostSignificantBit(0);
    }

    function test_MostSignificantBit_One() public view {
        assertEq(wrapper.mostSignificantBit(1), 0);
    }

    function test_MostSignificantBit_Two() public view {
        assertEq(wrapper.mostSignificantBit(2), 1);
    }

    function test_MostSignificantBit_PowersOfTwo() public view {
        for (uint8 i = 0; i < 255; i++) {
            assertEq(wrapper.mostSignificantBit(1 << i), i);
        }
    }

    function test_MostSignificantBit_MaxUint256() public view {
        assertEq(wrapper.mostSignificantBit(type(uint256).max), 255);
    }

    function test_MostSignificantBit_MaxUint128() public view {
        assertEq(wrapper.mostSignificantBit(type(uint128).max), 127);
    }

    // leastSignificantBit tests

    function test_LeastSignificantBit_RevertOnZero() public {
        vm.expectRevert();
        wrapper.leastSignificantBit(0);
    }

    function test_LeastSignificantBit_One() public view {
        assertEq(wrapper.leastSignificantBit(1), 0);
    }

    function test_LeastSignificantBit_Two() public view {
        assertEq(wrapper.leastSignificantBit(2), 1);
    }

    function test_LeastSignificantBit_PowersOfTwo() public view {
        for (uint8 i = 0; i < 255; i++) {
            assertEq(wrapper.leastSignificantBit(1 << i), i);
        }
    }

    function test_LeastSignificantBit_MaxUint256() public view {
        assertEq(wrapper.leastSignificantBit(type(uint256).max), 0);
    }

    function test_LeastSignificantBit_MaxUint128() public view {
        assertEq(wrapper.leastSignificantBit(uint256(type(uint128).max) << 128), 128);
    }

    // Fuzz tests

    function testFuzz_MostSignificantBit_Property(uint256 x) public view {
        vm.assume(x > 0);
        uint8 msb = wrapper.mostSignificantBit(x);

        // x >= 2**msb
        assertTrue(x >= (1 << msb));

        // x < 2**(msb+1) if msb < 255
        if (msb < 255) {
            assertTrue(x < (uint256(1) << (msb + 1)));
        }
    }

    function testFuzz_LeastSignificantBit_Property(uint256 x) public view {
        vm.assume(x > 0);
        uint8 lsb = wrapper.leastSignificantBit(x);

        // (x & 2**lsb) != 0
        assertTrue((x & (1 << lsb)) != 0);

        // (x & (2**lsb - 1)) == 0
        if (lsb > 0) {
            assertTrue((x & ((1 << lsb) - 1)) == 0);
        }
    }

    function testFuzz_MSB_LSB_Consistency(uint256 x) public view {
        vm.assume(x > 0);
        uint8 msb = wrapper.mostSignificantBit(x);
        uint8 lsb = wrapper.leastSignificantBit(x);

        // MSB >= LSB always
        assertTrue(msb >= lsb);

        // For powers of two, MSB == LSB
        if (x & (x - 1) == 0) {
            assertEq(msb, lsb);
        }
    }
}
