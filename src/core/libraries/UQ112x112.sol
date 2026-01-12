// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title UQ112x112 library
/// @notice A library for handling binary fixed point numbers
/// @dev Uses Q number format: https://en.wikipedia.org/wiki/Q_(number_format)
/// Range: [0, 2^112 - 1], Resolution: 1 / 2^112
library UQ112x112 {
    uint224 internal constant Q112 = 2 ** 112;

    /// @notice Encodes a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112;
    }

    /// @notice Divides a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
