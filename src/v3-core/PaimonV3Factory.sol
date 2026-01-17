// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPaimonV3Factory} from "../v3-interfaces/IPaimonV3Factory.sol";
import {PaimonV3PoolDeployer} from "./PaimonV3PoolDeployer.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";

/// @title Canonical Paimon V3 Factory
/// @notice Deploys Paimon V3 pools and manages ownership and control over pool protocol fees
contract PaimonV3Factory is IPaimonV3Factory, PaimonV3PoolDeployer, NoDelegateCall {
    error InvalidToken();
    error InvalidFee();
    error PoolAlreadyExists();
    error NotOwner();
    error InvalidTickSpacing();

    /// @inheritdoc IPaimonV3Factory
    address public override owner;

    /// @inheritdoc IPaimonV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;

    /// @inheritdoc IPaimonV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // Initialize default fee amounts
        feeAmountTickSpacing[500] = 10;     // 0.05%
        emit FeeAmountEnabled(500, 10);

        feeAmountTickSpacing[3000] = 60;    // 0.3%
        emit FeeAmountEnabled(3000, 60);

        feeAmountTickSpacing[10000] = 200;  // 1%
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IPaimonV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        if (tokenA == tokenB) revert InvalidToken();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert InvalidToken();

        int24 tickSpacing = feeAmountTickSpacing[fee];
        if (tickSpacing == 0) revert InvalidFee();

        if (getPool[token0][token1][fee] != address(0)) revert PoolAlreadyExists();

        pool = deploy(address(this), token0, token1, fee, tickSpacing);

        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;

        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IPaimonV3Factory
    function setOwner(address _owner) external override {
        if (msg.sender != owner) revert NotOwner();
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IPaimonV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external override {
        if (msg.sender != owner) revert NotOwner();
        if (fee >= 1000000) revert InvalidFee();
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        if (tickSpacing <= 0 || tickSpacing > 16384) revert InvalidTickSpacing();
        if (feeAmountTickSpacing[fee] != 0) revert InvalidFee();

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
