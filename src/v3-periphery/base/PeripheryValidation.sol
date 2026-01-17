// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Periphery Payments
/// @notice Validation functions for periphery contracts
abstract contract PeripheryValidation {
    error TransactionTooOld();

    /// @dev Modifier to verify the deadline hasn't passed
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionTooOld();
        _;
    }
}
