// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPaimonV3PoolImmutables} from "./pool/IPaimonV3PoolImmutables.sol";
import {IPaimonV3PoolState} from "./pool/IPaimonV3PoolState.sol";
import {IPaimonV3PoolDerivedState} from "./pool/IPaimonV3PoolDerivedState.sol";
import {IPaimonV3PoolActions} from "./pool/IPaimonV3PoolActions.sol";
import {IPaimonV3PoolOwnerActions} from "./pool/IPaimonV3PoolOwnerActions.sol";
import {IPaimonV3PoolEvents} from "./pool/IPaimonV3PoolEvents.sol";

/// @title The interface for a Paimon V3 Pool
/// @notice A Paimon pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IPaimonV3Pool is
    IPaimonV3PoolImmutables,
    IPaimonV3PoolState,
    IPaimonV3PoolDerivedState,
    IPaimonV3PoolActions,
    IPaimonV3PoolOwnerActions,
    IPaimonV3PoolEvents
{

}
