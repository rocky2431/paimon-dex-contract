// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Math library for liquidity
library LiquidityMath {
    error LiquidityUnderflow();
    error LiquidityOverflow();

    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            uint128 yAbs = uint128(-y);
            if (yAbs > x) revert LiquidityUnderflow();
            z = x - yAbs;
        } else {
            z = x + uint128(y);
            if (z < x) revert LiquidityOverflow();
        }
    }
}
