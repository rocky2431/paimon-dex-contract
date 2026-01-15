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

    function test_TwoStepOwnershipTransfer() public {
        address newFeeToSetter = address(0x456);

        // Step 1: Propose new feeToSetter
        vm.prank(feeToSetter);
        factory.proposeFeeToSetter(newFeeToSetter);

        // feeToSetter should not change yet
        assertEq(factory.feeToSetter(), feeToSetter);
        assertEq(factory.pendingFeeToSetter(), newFeeToSetter);

        // Step 2: Accept the role
        vm.prank(newFeeToSetter);
        factory.acceptFeeToSetter();

        assertEq(factory.feeToSetter(), newFeeToSetter);
        assertEq(factory.pendingFeeToSetter(), address(0));
    }

    function test_SetFeeToSetter_LegacyProposesOnly() public {
        address newFeeToSetter = address(0x456);

        // Legacy setFeeToSetter now just proposes
        vm.prank(feeToSetter);
        factory.setFeeToSetter(newFeeToSetter);

        // feeToSetter should not change, only pending
        assertEq(factory.feeToSetter(), feeToSetter);
        assertEq(factory.pendingFeeToSetter(), newFeeToSetter);
    }

    function test_RevertWhen_AcceptFeeToSetter_NotPending() public {
        address randomAddress = address(0x789);

        vm.prank(randomAddress);
        vm.expectRevert(PaimonFactory.Forbidden.selector);
        factory.acceptFeeToSetter();
    }

    function test_RevertWhen_ProposeFeeToSetter_ZeroAddress() public {
        vm.prank(feeToSetter);
        vm.expectRevert(PaimonFactory.ZeroAddress.selector);
        factory.proposeFeeToSetter(address(0));
    }

    function test_RevertWhen_Constructor_ZeroAddress() public {
        vm.expectRevert(PaimonFactory.ZeroAddress.selector);
        new PaimonFactory(address(0));
    }
}
