// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Position Key
/// @notice Computes the position key from the owner, tick lower and tick upper
library PositionKey {
    /// @notice Returns the key of the position in the core library
    /// @param owner The address of the position owner
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @return key The position key
    function compute(
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }
}
