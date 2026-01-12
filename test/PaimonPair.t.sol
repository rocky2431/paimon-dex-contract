// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "../src/interfaces/IPaimonPair.sol";
import "./mocks/MockERC20.sol";

contract PaimonPairTest is Test {
    PaimonFactory public factory;
    PaimonPair public pair;
    MockERC20 public token0;
    MockERC20 public token1;

    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        factory = new PaimonFactory(address(this));

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);

        address pairAddr = factory.createPair(address(tokenA), address(tokenB));
        pair = PaimonPair(pairAddr);

        (token0, token1) = address(tokenA) < address(tokenB)
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    function test_Mint() public {
        uint256 token0Amount = 1 ether;
        uint256 token1Amount = 4 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);

        uint256 expectedLiquidity = 2 ether;
        uint256 liquidity = pair.mint(alice);

        assertEq(liquidity, expectedLiquidity - MINIMUM_LIQUIDITY);
        assertEq(pair.balanceOf(alice), expectedLiquidity - MINIMUM_LIQUIDITY);
        assertEq(pair.totalSupply(), expectedLiquidity);
    }

    function test_Swap() public {
        uint256 token0Amount = 5 ether;
        uint256 token1Amount = 10 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);
        pair.mint(alice);

        uint256 swapAmount = 1 ether;
        uint256 expectedOutputAmount = 1662497915624478906;

        token0.mint(address(pair), swapAmount);

        vm.expectEmit(true, true, false, true);
        emit IPaimonPair.Swap(address(this), swapAmount, 0, 0, expectedOutputAmount, bob);

        pair.swap(0, expectedOutputAmount, bob, "");

        assertEq(token1.balanceOf(bob), expectedOutputAmount);
    }

    function test_Burn() public {
        uint256 token0Amount = 3 ether;
        uint256 token1Amount = 3 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);

        uint256 liquidity = pair.mint(alice);

        vm.prank(alice);
        pair.transfer(address(pair), liquidity);

        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        assertEq(pair.balanceOf(alice), 0);
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);
        assertEq(token0.balanceOf(alice), amount0);
        assertEq(token1.balanceOf(alice), amount1);
    }

    function test_GetReserves() public {
        uint256 token0Amount = 1 ether;
        uint256 token1Amount = 2 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);
        pair.mint(alice);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        assertEq(reserve0, token0Amount);
        assertEq(reserve1, token1Amount);
    }

    function test_Skim() public {
        uint256 token0Amount = 1 ether;
        uint256 token1Amount = 2 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);
        pair.mint(alice);

        uint256 extraToken0 = 0.5 ether;
        token0.mint(address(pair), extraToken0);

        pair.skim(bob);

        assertEq(token0.balanceOf(bob), extraToken0);
    }

    function test_Sync() public {
        uint256 token0Amount = 1 ether;
        uint256 token1Amount = 2 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);
        pair.mint(alice);

        uint256 extraToken0 = 0.5 ether;
        token0.mint(address(pair), extraToken0);

        pair.sync();

        (uint112 reserve0,,) = pair.getReserves();
        assertEq(reserve0, token0Amount + extraToken0);
    }

    function test_RevertWhen_SwapInsufficientOutputAmount() public {
        vm.expectRevert(PaimonPair.InsufficientOutputAmount.selector);
        pair.swap(0, 0, alice, "");
    }

    function test_RevertWhen_SwapInsufficientLiquidity() public {
        uint256 token0Amount = 1 ether;
        uint256 token1Amount = 2 ether;

        token0.mint(address(pair), token0Amount);
        token1.mint(address(pair), token1Amount);
        pair.mint(alice);

        vm.expectRevert(PaimonPair.InsufficientLiquidity.selector);
        pair.swap(token0Amount + 1, 0, bob, "");
    }
}
