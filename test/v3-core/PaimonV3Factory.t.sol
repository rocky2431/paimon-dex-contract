// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PaimonV3Factory} from "../../src/v3-core/PaimonV3Factory.sol";
import {PaimonV3Pool} from "../../src/v3-core/PaimonV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract PaimonV3FactoryTest is Test {
    PaimonV3Factory public factory;
    MockERC20 public token0;
    MockERC20 public token1;

    address public owner = address(this);

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    function setUp() public {
        factory = new PaimonV3Factory();

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);

        // Ensure token0 < token1
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
    }

    // Deployment tests

    function test_DeploymentSetsOwner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_DeploymentInitializesDefaultFees() public view {
        // 0.05% -> tickSpacing 10
        assertEq(factory.feeAmountTickSpacing(500), 10);
        // 0.3% -> tickSpacing 60
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        // 1% -> tickSpacing 200
        assertEq(factory.feeAmountTickSpacing(10000), 200);
    }

    // createPool tests

    function test_CreatePool_Success() public {
        address pool = factory.createPool(address(token0), address(token1), 3000);

        assertTrue(pool != address(0));
        assertEq(factory.getPool(address(token0), address(token1), 3000), pool);
        assertEq(factory.getPool(address(token1), address(token0), 3000), pool);
    }

    function test_CreatePool_EmitsEvent() public {
        // Only check indexed params (token0, token1, fee), not the pool address
        vm.expectEmit(true, true, true, false);
        emit PoolCreated(address(token0), address(token1), 3000, 60, address(0));

        factory.createPool(address(token0), address(token1), 3000);
    }

    function test_CreatePool_RevertsForSameToken() public {
        vm.expectRevert(PaimonV3Factory.InvalidToken.selector);
        factory.createPool(address(token0), address(token0), 3000);
    }

    function test_CreatePool_RevertsForZeroAddress() public {
        vm.expectRevert(PaimonV3Factory.InvalidToken.selector);
        factory.createPool(address(0), address(token1), 3000);
    }

    function test_CreatePool_RevertsForInvalidFee() public {
        vm.expectRevert(PaimonV3Factory.InvalidFee.selector);
        factory.createPool(address(token0), address(token1), 1234);
    }

    function test_CreatePool_RevertsForDuplicate() public {
        factory.createPool(address(token0), address(token1), 3000);

        vm.expectRevert(PaimonV3Factory.PoolAlreadyExists.selector);
        factory.createPool(address(token0), address(token1), 3000);
    }

    function test_CreatePool_AllowsDifferentFees() public {
        address pool1 = factory.createPool(address(token0), address(token1), 500);
        address pool2 = factory.createPool(address(token0), address(token1), 3000);
        address pool3 = factory.createPool(address(token0), address(token1), 10000);

        assertTrue(pool1 != pool2);
        assertTrue(pool2 != pool3);
        assertTrue(pool1 != pool3);
    }

    function test_CreatePool_TokenOrderDoesNotMatter() public {
        address pool1 = factory.createPool(address(token1), address(token0), 3000);
        assertEq(factory.getPool(address(token0), address(token1), 3000), pool1);
    }

    // Pool initialization tests

    function test_CreatedPool_HasCorrectImmutables() public {
        address poolAddr = factory.createPool(address(token0), address(token1), 3000);
        PaimonV3Pool pool = PaimonV3Pool(poolAddr);

        assertEq(pool.factory(), address(factory));
        assertEq(pool.token0(), address(token0));
        assertEq(pool.token1(), address(token1));
        assertEq(pool.fee(), 3000);
        assertEq(pool.tickSpacing(), 60);
    }

    // setOwner tests

    function test_SetOwner_Success() public {
        address newOwner = address(0x123);

        vm.expectEmit(true, true, false, false);
        emit OwnerChanged(owner, newOwner);

        factory.setOwner(newOwner);

        assertEq(factory.owner(), newOwner);
    }

    function test_SetOwner_RevertsForNonOwner() public {
        vm.prank(address(0x123));
        vm.expectRevert(PaimonV3Factory.NotOwner.selector);
        factory.setOwner(address(0x456));
    }

    // enableFeeAmount tests

    function test_EnableFeeAmount_Success() public {
        vm.expectEmit(true, true, false, false);
        emit FeeAmountEnabled(2500, 50);

        factory.enableFeeAmount(2500, 50);

        assertEq(factory.feeAmountTickSpacing(2500), 50);
    }

    function test_EnableFeeAmount_RevertsForNonOwner() public {
        vm.prank(address(0x123));
        vm.expectRevert(PaimonV3Factory.NotOwner.selector);
        factory.enableFeeAmount(2500, 50);
    }

    function test_EnableFeeAmount_RevertsForExistingFee() public {
        vm.expectRevert(PaimonV3Factory.InvalidFee.selector);
        factory.enableFeeAmount(3000, 100);
    }

    function test_EnableFeeAmount_RevertsForInvalidTickSpacing() public {
        vm.expectRevert(PaimonV3Factory.InvalidTickSpacing.selector);
        factory.enableFeeAmount(2500, 0);

        vm.expectRevert(PaimonV3Factory.InvalidTickSpacing.selector);
        factory.enableFeeAmount(2500, -1);

        vm.expectRevert(PaimonV3Factory.InvalidTickSpacing.selector);
        factory.enableFeeAmount(2500, 16385);
    }

    function test_EnableFeeAmount_RevertsForFeeTooHigh() public {
        vm.expectRevert(PaimonV3Factory.InvalidFee.selector);
        factory.enableFeeAmount(1000000, 50);
    }
}
