// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TickBitmap} from "../../../src/v3-core/libraries/TickBitmap.sol";

contract TickBitmapWrapper {
    mapping(int16 => uint256) public bitmap;

    function flipTick(int24 tick, int24 tickSpacing) external {
        TickBitmap.flipTick(bitmap, tick, tickSpacing);
    }

    function nextInitializedTickWithinOneWord(
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) external view returns (int24 next, bool initialized) {
        return TickBitmap.nextInitializedTickWithinOneWord(bitmap, tick, tickSpacing, lte);
    }

    function isInitialized(int24 tick, int24 tickSpacing) external view returns (bool) {
        require(tick % tickSpacing == 0);
        int24 compressed = tick / tickSpacing;
        int16 wordPos = int16(compressed >> 8);
        uint8 bitPos = uint8(int8(compressed % 256));
        return (bitmap[wordPos] & (1 << bitPos)) != 0;
    }
}

contract TickBitmapTest is Test {
    TickBitmapWrapper public wrapper;

    int24 constant TICK_SPACING = 1;

    function setUp() public {
        wrapper = new TickBitmapWrapper();
    }

    // flipTick tests

    function test_FlipTick_InitializesTick() public {
        wrapper.flipTick(0, TICK_SPACING);
        assertTrue(wrapper.isInitialized(0, TICK_SPACING));
    }

    function test_FlipTick_UninitializesTick() public {
        wrapper.flipTick(0, TICK_SPACING);
        wrapper.flipTick(0, TICK_SPACING);
        assertFalse(wrapper.isInitialized(0, TICK_SPACING));
    }

    function test_FlipTick_MultipleTicks() public {
        wrapper.flipTick(-100, TICK_SPACING);
        wrapper.flipTick(100, TICK_SPACING);
        wrapper.flipTick(200, TICK_SPACING);

        assertTrue(wrapper.isInitialized(-100, TICK_SPACING));
        assertTrue(wrapper.isInitialized(100, TICK_SPACING));
        assertTrue(wrapper.isInitialized(200, TICK_SPACING));
        assertFalse(wrapper.isInitialized(0, TICK_SPACING));
    }

    function test_FlipTick_WithTickSpacing() public {
        int24 tickSpacing = 60;
        wrapper.flipTick(0, tickSpacing);
        wrapper.flipTick(60, tickSpacing);
        wrapper.flipTick(-60, tickSpacing);

        assertTrue(wrapper.isInitialized(0, tickSpacing));
        assertTrue(wrapper.isInitialized(60, tickSpacing));
        assertTrue(wrapper.isInitialized(-60, tickSpacing));
    }

    // nextInitializedTickWithinOneWord tests - lte (searching left)

    function test_NextInitializedTick_LTE_ReturnsInitialized() public {
        wrapper.flipTick(-100, TICK_SPACING);
        wrapper.flipTick(-50, TICK_SPACING);

        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(-50, TICK_SPACING, true);
        assertEq(next, -50);
        assertTrue(initialized);
    }

    function test_NextInitializedTick_LTE_ReturnsPreviousInitialized() public {
        wrapper.flipTick(-100, TICK_SPACING);

        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(-50, TICK_SPACING, true);
        assertEq(next, -100);
        assertTrue(initialized);
    }

    function test_NextInitializedTick_LTE_NoInitialized() public view {
        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(0, TICK_SPACING, true);
        // When no initialized tick, returns the leftmost possible tick in the word
        // For tick 0 with spacing 1, compressed = 0, bitPos = 0, so next = (0 - 0) * 1 = 0
        assertEq(next, 0);
        assertFalse(initialized);
    }

    // nextInitializedTickWithinOneWord tests - gt (searching right)

    function test_NextInitializedTick_GT_ReturnsNextInitialized() public {
        wrapper.flipTick(100, TICK_SPACING);

        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(50, TICK_SPACING, false);
        assertEq(next, 100);
        assertTrue(initialized);
    }

    function test_NextInitializedTick_GT_NoInitialized() public view {
        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(0, TICK_SPACING, false);
        // When no initialized tick searching right from 0, goes to end of next word
        // compressed + 1 = 1, bitPos = 1, so next = (1 + (255 - 1)) * 1 = 255
        assertEq(next, 255);
        assertFalse(initialized);
    }

    function test_NextInitializedTick_GT_SkipsCurrentTick() public {
        wrapper.flipTick(0, TICK_SPACING);
        wrapper.flipTick(100, TICK_SPACING);

        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(0, TICK_SPACING, false);
        assertEq(next, 100);
        assertTrue(initialized);
    }

    // Edge cases with tick spacing

    function test_NextInitializedTick_WithTickSpacing60() public {
        int24 tickSpacing = 60;
        wrapper.flipTick(60, tickSpacing);
        wrapper.flipTick(120, tickSpacing);

        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(0, tickSpacing, false);
        assertEq(next, 60);
        assertTrue(initialized);
    }

    function test_NextInitializedTick_WordBoundary() public {
        // Tick 255 and 256 are in different words for spacing=1
        wrapper.flipTick(255, TICK_SPACING);
        wrapper.flipTick(256, TICK_SPACING);

        // Searching from 200, should find 255 in same word
        (int24 next, bool initialized) = wrapper.nextInitializedTickWithinOneWord(200, TICK_SPACING, false);
        assertEq(next, 255);
        assertTrue(initialized);

        // Searching from 256, should not find 255 (different word)
        (next, initialized) = wrapper.nextInitializedTickWithinOneWord(256, TICK_SPACING, true);
        assertEq(next, 256);
        assertTrue(initialized);
    }

    // Fuzz tests

    function testFuzz_FlipTick_Idempotent(int24 tick) public {
        tick = int24(bound(int256(tick), -887272, 887272));

        wrapper.flipTick(tick, TICK_SPACING);
        assertTrue(wrapper.isInitialized(tick, TICK_SPACING));

        wrapper.flipTick(tick, TICK_SPACING);
        assertFalse(wrapper.isInitialized(tick, TICK_SPACING));
    }
}
