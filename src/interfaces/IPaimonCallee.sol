// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPaimonCallee
/// @notice Interface for flash swap callback
/// @dev SECURITY: Implementers MUST verify that msg.sender is a legitimate Paimon Pair.
///      The recommended approach is to:
///      1. Verify msg.sender == PaimonLibrary.pairFor(factory, tokenA, tokenB)
///      2. Or verify IPaimonFactory(factory).getPair(tokenA, tokenB) == msg.sender
///      The `factory` address is passed as a parameter for convenience.
interface IPaimonCallee {
    /// @notice Called by PaimonPair during a flash swap
    /// @param sender The address that initiated the swap (msg.sender of swap())
    /// @param amount0 Amount of token0 sent to the callee
    /// @param amount1 Amount of token1 sent to the callee
    /// @param factory The factory address - use this to verify msg.sender is a legitimate pair
    /// @param data Arbitrary data passed through from the swap call
    function paimonCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        address factory,
        bytes calldata data
    ) external;
}
