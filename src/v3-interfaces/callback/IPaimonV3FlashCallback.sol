// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Callback for IPaimonV3PoolActions#flash
/// @notice Any contract that calls IPaimonV3PoolActions#flash must implement this interface
interface IPaimonV3FlashCallback {
    /// @notice Called to `msg.sender` after transferring to the recipient from IPaimonV3Pool#flash.
    /// @dev In the implementation you must repay the pool the tokens sent by flash plus the computed fee amounts.
    /// The caller of this method must be checked to be a PaimonV3Pool deployed by the canonical PaimonV3Factory.
    /// @param fee0 The fee amount in token0 due to the pool by the end of the flash
    /// @param fee1 The fee amount in token1 due to the pool by the end of the flash
    /// @param data Any data passed through by the caller via the IPaimonV3PoolActions#flash call
    function paimonV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}
