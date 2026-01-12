// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "./mocks/MockERC20.sol";

contract PaimonFactoryTest is Test {
    PaimonFactory public factory;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    address public feeToSetter = address(0x1);

    function setUp() public {
        factory = new PaimonFactory(feeToSetter);
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
    }

    function test_CreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertNotEq(pair, address(0));
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function test_CreatePair_SortedTokens() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        assertEq(IPaimonPair(pair).token0(), token0);
        assertEq(IPaimonPair(pair).token1(), token1);
    }

    function test_RevertWhen_IdenticalAddresses() public {
        vm.expectRevert(PaimonFactory.IdenticalAddresses.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(PaimonFactory.ZeroAddress.selector);
        factory.createPair(address(0), address(tokenB));
    }

    function test_RevertWhen_PairExists() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(PaimonFactory.PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_SetFeeTo() public {
        address newFeeTo = address(0x123);

        vm.prank(feeToSetter);
        factory.setFeeTo(newFeeTo);

        assertEq(factory.feeTo(), newFeeTo);
    }

    function test_RevertWhen_SetFeeTo_NotAuthorized() public {
        vm.expectRevert(PaimonFactory.Forbidden.selector);
        factory.setFeeTo(address(0x123));
    }

    function test_SetFeeToSetter() public {
        address newFeeToSetter = address(0x456);

        vm.prank(feeToSetter);
        factory.setFeeToSetter(newFeeToSetter);

        assertEq(factory.feeToSetter(), newFeeToSetter);
    }
}
