// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "../src/periphery/libraries/PaimonLibrary.sol";
import "./mocks/MockERC20.sol";

/// @title PaimonLibrary Tests
/// @notice Tests for pure calculation functions
contract PaimonLibraryTest is Test {
    PaimonFactory public factory;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    function setUp() public {
        factory = new PaimonFactory(address(this));
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
    }

    // ========== sortTokens Tests ==========

    function test_SortTokens() public view {
        (address token0, address token1) = this.sortTokensExternal(address(tokenA), address(tokenB));

        if (address(tokenA) < address(tokenB)) {
            assertEq(token0, address(tokenA));
            assertEq(token1, address(tokenB));
        } else {
            assertEq(token0, address(tokenB));
            assertEq(token1, address(tokenA));
        }
    }

    function test_SortTokens_ReversedInput() public view {
        (address token0_1, address token1_1) = this.sortTokensExternal(address(tokenA), address(tokenB));
        (address token0_2, address token1_2) = this.sortTokensExternal(address(tokenB), address(tokenA));

        assertEq(token0_1, token0_2);
        assertEq(token1_1, token1_2);
    }

    function test_RevertWhen_SortTokens_IdenticalAddresses() public {
        vm.expectRevert(PaimonLibrary.IdenticalAddresses.selector);
        this.sortTokensExternal(address(tokenA), address(tokenA));
    }

    function test_RevertWhen_SortTokens_ZeroAddress() public {
        vm.expectRevert(PaimonLibrary.ZeroAddress.selector);
        this.sortTokensExternal(address(0), address(tokenA));
    }

    // External wrapper for sortTokens
    function sortTokensExternal(address _tokenA, address _tokenB) external pure returns (address, address) {
        return PaimonLibrary.sortTokens(_tokenA, _tokenB);
    }

    // ========== pairFor Tests ==========

    function test_PairFor_DeterministicAddress() public {
        // Create pair via factory
        address actualPair = factory.createPair(address(tokenA), address(tokenB));

        // Compute via library
        address computedPair = PaimonLibrary.pairFor(address(factory), address(tokenA), address(tokenB));

        assertEq(computedPair, actualPair);
    }

    function test_PairFor_OrderIndependent() public {
        address pair1 = PaimonLibrary.pairFor(address(factory), address(tokenA), address(tokenB));
        address pair2 = PaimonLibrary.pairFor(address(factory), address(tokenB), address(tokenA));

        assertEq(pair1, pair2);
    }

    // ========== quote Tests ==========

    function test_Quote() public view {
        // 1:1 ratio
        assertEq(this.quoteExternal(1 ether, 100 ether, 100 ether), 1 ether);

        // 1:2 ratio
        assertEq(this.quoteExternal(1 ether, 100 ether, 200 ether), 2 ether);

        // 2:1 ratio
        assertEq(this.quoteExternal(1 ether, 200 ether, 100 ether), 0.5 ether);
    }

    function test_RevertWhen_Quote_ZeroAmount() public {
        vm.expectRevert(PaimonLibrary.InsufficientAmount.selector);
        this.quoteExternal(0, 100 ether, 100 ether);
    }

    function test_RevertWhen_Quote_ZeroReserve() public {
        vm.expectRevert(PaimonLibrary.InsufficientLiquidity.selector);
        this.quoteExternal(1 ether, 0, 100 ether);
    }

    // External wrapper for quote
    function quoteExternal(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return PaimonLibrary.quote(amountA, reserveA, reserveB);
    }

    // ========== getAmountOut Tests ==========

    function test_GetAmountOut() public view {
        // Standard case with 0.3% fee
        uint256 amountOut = this.getAmountOutExternal(1 ether, 100 ether, 100 ether);
        assertApproxEqRel(amountOut, 0.987158034397061298 ether, 0.001e18);
    }

    function test_GetAmountOut_LargeInput() public view {
        // Large input relative to reserve
        uint256 amountOut = this.getAmountOutExternal(50 ether, 100 ether, 100 ether);
        // Should get less than 50 due to price impact + fee
        assertTrue(amountOut < 50 ether);
        assertTrue(amountOut > 30 ether); // But still reasonable
    }

    function test_RevertWhen_GetAmountOut_ZeroInput() public {
        vm.expectRevert(PaimonLibrary.InsufficientAmount.selector);
        this.getAmountOutExternal(0, 100 ether, 100 ether);
    }

    function test_RevertWhen_GetAmountOut_ZeroReserve() public {
        vm.expectRevert(PaimonLibrary.InsufficientLiquidity.selector);
        this.getAmountOutExternal(1 ether, 0, 100 ether);
    }

    // External wrapper for getAmountOut
    function getAmountOutExternal(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return PaimonLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // ========== getAmountIn Tests ==========

    function test_GetAmountIn() public view {
        // Should need slightly more than 1 ETH to get 1 ETH out
        uint256 amountIn = this.getAmountInExternal(1 ether, 100 ether, 100 ether);
        assertTrue(amountIn > 1 ether);
        // Approximately 1.013 ETH due to 0.3% fee
        assertApproxEqRel(amountIn, 1.012943619177654073 ether, 0.001e18);
    }

    function test_RevertWhen_GetAmountIn_ZeroOutput() public {
        vm.expectRevert(PaimonLibrary.InsufficientAmount.selector);
        this.getAmountInExternal(0, 100 ether, 100 ether);
    }

    function test_RevertWhen_GetAmountIn_ZeroReserve() public {
        vm.expectRevert(PaimonLibrary.InsufficientLiquidity.selector);
        this.getAmountInExternal(1 ether, 0, 100 ether);
    }

    function test_RevertWhen_GetAmountIn_ExceedsReserve() public {
        // Trying to get more than or equal to reserve should fail
        vm.expectRevert(PaimonLibrary.InsufficientLiquidity.selector);
        this.getAmountInExternal(100 ether, 100 ether, 100 ether);
    }

    // External wrapper for getAmountIn
    function getAmountInExternal(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return PaimonLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    // ========== getAmountsOut Tests ==========

    function test_GetAmountsOut() public {
        // Create pair with liquidity
        address pair = factory.createPair(address(tokenA), address(tokenB));
        tokenA.mint(pair, 100 ether);
        tokenB.mint(pair, 100 ether);
        PaimonPair(pair).mint(address(this));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = PaimonLibrary.getAmountsOut(address(factory), 1 ether, path);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], 1 ether);
        assertTrue(amounts[1] > 0);
    }

    function test_GetAmountsOut_MultiHop() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC", 18);

        // Create A-B pair
        address pairAB = factory.createPair(address(tokenA), address(tokenB));
        tokenA.mint(pairAB, 100 ether);
        tokenB.mint(pairAB, 100 ether);
        PaimonPair(pairAB).mint(address(this));

        // Create B-C pair
        address pairBC = factory.createPair(address(tokenB), address(tokenC));
        tokenB.mint(pairBC, 100 ether);
        tokenC.mint(pairBC, 100 ether);
        PaimonPair(pairBC).mint(address(this));

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amounts = PaimonLibrary.getAmountsOut(address(factory), 1 ether, path);

        assertEq(amounts.length, 3);
        assertEq(amounts[0], 1 ether);
        assertTrue(amounts[1] > 0);
        assertTrue(amounts[2] > 0);
        // Each hop has price impact + fee, so final amount < amounts[1]
        assertTrue(amounts[2] < amounts[1]);
    }

    function test_RevertWhen_GetAmountsOut_InvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert(PaimonLibrary.InvalidPath.selector);
        this.getAmountsOutExternal(address(factory), 1 ether, path);
    }

    // External wrapper for getAmountsOut
    function getAmountsOutExternal(address _factory, uint256 amountIn, address[] memory path) external view returns (uint256[] memory) {
        return PaimonLibrary.getAmountsOut(_factory, amountIn, path);
    }

    // ========== getAmountsIn Tests ==========

    function test_GetAmountsIn() public {
        // Create pair with liquidity
        address pair = factory.createPair(address(tokenA), address(tokenB));
        tokenA.mint(pair, 100 ether);
        tokenB.mint(pair, 100 ether);
        PaimonPair(pair).mint(address(this));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = this.getAmountsInExternal(address(factory), 1 ether, path);

        assertEq(amounts.length, 2);
        assertEq(amounts[1], 1 ether);
        assertTrue(amounts[0] > 1 ether); // Need more due to fee
    }

    function test_RevertWhen_GetAmountsIn_InvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert(PaimonLibrary.InvalidPath.selector);
        this.getAmountsInExternal(address(factory), 1 ether, path);
    }

    // External wrapper for getAmountsIn
    function getAmountsInExternal(address _factory, uint256 amountOut, address[] memory path) external view returns (uint256[] memory) {
        return PaimonLibrary.getAmountsIn(_factory, amountOut, path);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_Quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public view {
        amountA = bound(amountA, 1, 1e24);
        reserveA = bound(reserveA, 1, 1e24);
        reserveB = bound(reserveB, 1, 1e24);

        uint256 amountB = this.quoteExternal(amountA, reserveA, reserveB);

        // amountB = (amountA * reserveB) / reserveA
        assertEq(amountB, (amountA * reserveB) / reserveA);
    }

    function testFuzz_GetAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view {
        // Ensure minimum values to avoid edge cases
        amountIn = bound(amountIn, 1e9, 1e20);
        reserveIn = bound(reserveIn, 1e18, 1e24);
        reserveOut = bound(reserveOut, 1e18, 1e24);

        uint256 amountOut = this.getAmountOutExternal(amountIn, reserveIn, reserveOut);

        // Output should be less than reserveOut
        assertTrue(amountOut < reserveOut);
        // Output should be positive for reasonable input
        assertTrue(amountOut > 0);
    }

    function testFuzz_GetAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public view {
        reserveIn = bound(reserveIn, 1e18, 1e26);
        reserveOut = bound(reserveOut, 1e18, 1e26);
        amountOut = bound(amountOut, 1, reserveOut - 1);

        uint256 amountIn = this.getAmountInExternal(amountOut, reserveIn, reserveOut);

        // Input should be positive
        assertTrue(amountIn > 0);
    }

    function test_RoundTrip_SpecificValues() public view {
        // Test round trip with specific known good values
        uint256 amountIn = 1 ether;
        uint256 reserveIn = 100 ether;
        uint256 reserveOut = 100 ether;

        // Get output for input
        uint256 amountOut = this.getAmountOutExternal(amountIn, reserveIn, reserveOut);

        // Get input needed for that output
        uint256 amountInNeeded = this.getAmountInExternal(amountOut, reserveIn, reserveOut);

        // Due to rounding, amountInNeeded should be >= amountIn
        assertTrue(amountInNeeded >= amountIn);
        // But should be close (within 1%)
        assertApproxEqRel(amountInNeeded, amountIn, 0.01e18);
    }
}
