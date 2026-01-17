// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPaimonV3Factory} from "../../v3-interfaces/IPaimonV3Factory.sol";
import {IPaimonV3Pool} from "../../v3-interfaces/IPaimonV3Pool.sol";
import {PeripheryImmutableState} from "./PeripheryImmutableState.sol";

/// @title Creates and initializes V3 Pools
abstract contract PoolInitializer is PeripheryImmutableState {
    /// @notice Creates a new pool if it does not exist, then initializes if not initialized
    /// @dev This method can be bundled with others via IMulticall for the first action (e.g. mint) performed against a pool
    /// @param token0 The contract address of token0 of the pool
    /// @param token1 The contract address of token1 of the pool
    /// @param fee The fee amount of the v3 pool for the specified token pair
    /// @param sqrtPriceX96 The initial square root price of the pool as a Q64.96 value
    /// @return pool Returns the pool address based on the pair of tokens and fee, will return the newly created pool address if necessary
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable virtual returns (address pool) {
        require(token0 < token1);
        pool = IPaimonV3Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = IPaimonV3Factory(factory).createPool(token0, token1, fee);
            IPaimonV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IPaimonV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IPaimonV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
