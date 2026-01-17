// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Oracle} from "../../../src/v3-core/libraries/Oracle.sol";

contract OracleWrapper {
    Oracle.Observation[65535] public observations;

    function initialize(uint32 time) external returns (uint16 cardinality, uint16 cardinalityNext) {
        return Oracle.initialize(observations, time);
    }

    function write(
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) external returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        return Oracle.write(observations, index, blockTimestamp, tick, liquidity, cardinality, cardinalityNext);
    }

    function grow(uint16 current, uint16 next) external returns (uint16) {
        return Oracle.grow(observations, current, next);
    }

    function observe(
        uint32 time,
        uint32[] calldata secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        return Oracle.observe(observations, time, secondsAgos, tick, index, liquidity, cardinality);
    }

    function getObservation(uint16 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        Oracle.Observation memory obs = observations[index];
        return (obs.blockTimestamp, obs.tickCumulative, obs.secondsPerLiquidityCumulativeX128, obs.initialized);
    }
}

contract OracleTest is Test {
    OracleWrapper public wrapper;

    function setUp() public {
        wrapper = new OracleWrapper();
    }

    // initialize tests

    function test_Initialize_SetsFirstObservation() public {
        (uint16 cardinality, uint16 cardinalityNext) = wrapper.initialize(1000);

        assertEq(cardinality, 1);
        assertEq(cardinalityNext, 1);

        (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized) =
            wrapper.getObservation(0);

        assertEq(blockTimestamp, 1000);
        assertEq(tickCumulative, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
        assertTrue(initialized);
    }

    // write tests

    function test_Write_SameBlock_NoUpdate() public {
        wrapper.initialize(1000);

        (uint16 indexUpdated, uint16 cardinalityUpdated) = wrapper.write(0, 1000, 100, 1e18, 1, 1);

        // Should not update when same block
        assertEq(indexUpdated, 0);
        assertEq(cardinalityUpdated, 1);
    }

    function test_Write_NewBlock_UpdatesObservation() public {
        wrapper.initialize(1000);

        (uint16 indexUpdated, uint16 cardinalityUpdated) = wrapper.write(0, 2000, 100, 1e18, 1, 1);

        assertEq(indexUpdated, 0); // Wraps around since cardinality = 1
        assertEq(cardinalityUpdated, 1);

        (uint32 blockTimestamp, int56 tickCumulative,,) = wrapper.getObservation(0);
        assertEq(blockTimestamp, 2000);
        // tickCumulative = previous + tick * delta = 0 + 100 * 1000 = 100000
        assertEq(tickCumulative, 100000);
    }

    function test_Write_MultipleObservations() public {
        wrapper.initialize(1000);
        wrapper.grow(1, 3);

        wrapper.write(0, 2000, 100, 1e18, 1, 3);
        (uint16 indexUpdated, uint16 cardinalityUpdated) = wrapper.write(1, 3000, 200, 1e18, 2, 3);

        assertEq(indexUpdated, 2);
        assertEq(cardinalityUpdated, 3);
    }

    // grow tests

    function test_Grow_RevertOnZeroCardinality() public {
        vm.expectRevert(Oracle.OracleCardinalityCannotBeZero.selector);
        wrapper.grow(0, 10);
    }

    function test_Grow_NoOpIfNextNotGreater() public {
        wrapper.initialize(1000);
        uint16 result = wrapper.grow(1, 1);
        assertEq(result, 1);
    }

    function test_Grow_IncreasesCardinality() public {
        wrapper.initialize(1000);
        uint16 result = wrapper.grow(1, 5);
        assertEq(result, 5);
    }

    // observe tests

    function test_Observe_CurrentTime() public {
        wrapper.initialize(1000);

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            wrapper.observe(1000, secondsAgos, 0, 0, 1e18, 1);

        assertEq(tickCumulatives[0], 0);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 0);
    }

    function test_Observe_RevertOnZeroCardinality() public {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;

        vm.expectRevert(Oracle.OracleCardinalityCannotBeZero.selector);
        wrapper.observe(1000, secondsAgos, 0, 0, 1e18, 0);
    }

    function test_Observe_TransformsCurrent() public {
        wrapper.initialize(1000);

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;

        // Observe at time 2000, tick 100
        (int56[] memory tickCumulatives,) = wrapper.observe(2000, secondsAgos, 100, 0, 1e18, 1);

        // Expected: 0 + 100 * (2000 - 1000) = 100000
        assertEq(tickCumulatives[0], 100000);
    }

    function test_Observe_InterpolatesBetweenObservations() public {
        wrapper.initialize(1000);
        wrapper.grow(1, 3);

        // Write observation at time 3000
        wrapper.write(0, 3000, 100, 1e18, 1, 3);

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1000; // Look back 1000 seconds from time 3000

        // At time 2000, we should interpolate between observations at 1000 and 3000
        (int56[] memory tickCumulatives,) = wrapper.observe(3000, secondsAgos, 100, 1, 1e18, 2);

        // At observation 0 (time 1000): tickCumulative = 0
        // At observation 1 (time 3000): tickCumulative = 0 + 100 * 2000 = 200000
        // At time 2000: linear interpolation = 0 + (200000 - 0) * (2000 - 1000) / (3000 - 1000) = 100000
        assertEq(tickCumulatives[0], 100000);
    }

    // Fuzz tests

    function testFuzz_Initialize_AnyTime(uint32 time) public {
        (uint16 cardinality, uint16 cardinalityNext) = wrapper.initialize(time);

        assertEq(cardinality, 1);
        assertEq(cardinalityNext, 1);

        (uint32 blockTimestamp,,, bool initialized) = wrapper.getObservation(0);
        assertEq(blockTimestamp, time);
        assertTrue(initialized);
    }

    function testFuzz_Grow_Increases(uint16 current, uint16 next) public {
        current = uint16(bound(current, 1, 100));
        next = uint16(bound(next, 1, 200));

        wrapper.initialize(1000);
        // First grow to current
        wrapper.grow(1, current);

        uint16 result = wrapper.grow(current, next);

        if (next > current) {
            assertEq(result, next);
        } else {
            assertEq(result, current);
        }
    }
}
