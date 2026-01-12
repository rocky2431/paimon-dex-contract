// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPaimonCallee
/// @notice Interface for flash swap callback
interface IPaimonCallee {
    function paimonCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
