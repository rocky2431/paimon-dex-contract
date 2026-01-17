// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPaimonV3Pool} from "../../v3-interfaces/IPaimonV3Pool.sol";
import {PoolAddress} from "./PoolAddress.sol";

/// @title Callback Validation
/// @notice Provides validation for callbacks from Paimon V3 Pools
library CallbackValidation {
    error InvalidCaller();

    /// @notice Returns the address of a valid Paimon V3 Pool
    /// @param factory The contract address of the Paimon V3 factory
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The V3 pool contract address
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (IPaimonV3Pool pool) {
        return verifyCallback(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @notice Returns the address of a valid Paimon V3 Pool
    /// @param factory The contract address of the Paimon V3 factory
    /// @param poolKey The identifying key of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, PoolAddress.PoolKey memory poolKey)
        internal
        view
        returns (IPaimonV3Pool pool)
    {
        pool = IPaimonV3Pool(PoolAddress.computeAddress(factory, poolKey));
        if (msg.sender != address(pool)) revert InvalidCaller();
    }
}
