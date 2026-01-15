// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IPaimonFactory.sol";
import "./PaimonPair.sol";

/// @title PaimonFactory
/// @notice Factory contract for creating Paimon AMM pairs using CREATE2
contract PaimonFactory is IPaimonFactory {
    address public feeTo;
    address public feeToSetter;
    address public pendingFeeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error Forbidden();
    error NoPendingOwner();

    /// @notice Emitted when the fee recipient is updated
    event FeeToUpdated(address indexed oldFeeTo, address indexed newFeeTo);

    /// @notice Emitted when a new feeToSetter is proposed
    event FeeToSetterProposed(address indexed currentSetter, address indexed proposedSetter);

    /// @notice Emitted when the feeToSetter transfer is completed
    event FeeToSetterUpdated(address indexed oldSetter, address indexed newSetter);

    constructor(address _feeToSetter) {
        if (_feeToSetter == address(0)) revert ZeroAddress();
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new PaimonPair{salt: salt}());

        IPaimonPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        address oldFeeTo = feeTo;
        feeTo = _feeTo;
        emit FeeToUpdated(oldFeeTo, _feeTo);
    }

    /// @notice Proposes a new feeToSetter (first step of two-step transfer)
    /// @param _feeToSetter The address of the proposed new feeToSetter
    function proposeFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        if (_feeToSetter == address(0)) revert ZeroAddress();
        pendingFeeToSetter = _feeToSetter;
        emit FeeToSetterProposed(feeToSetter, _feeToSetter);
    }

    /// @notice Accepts the feeToSetter role (second step of two-step transfer)
    function acceptFeeToSetter() external {
        if (msg.sender != pendingFeeToSetter) revert Forbidden();
        if (pendingFeeToSetter == address(0)) revert NoPendingOwner();
        address oldSetter = feeToSetter;
        feeToSetter = pendingFeeToSetter;
        pendingFeeToSetter = address(0);
        emit FeeToSetterUpdated(oldSetter, feeToSetter);
    }

    /// @notice Legacy function for backward compatibility - now requires two-step transfer
    /// @dev Deprecated: Use proposeFeeToSetter + acceptFeeToSetter instead
    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        if (_feeToSetter == address(0)) revert ZeroAddress();
        pendingFeeToSetter = _feeToSetter;
        emit FeeToSetterProposed(feeToSetter, _feeToSetter);
    }
}
