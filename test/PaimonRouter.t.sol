// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "../src/periphery/PaimonRouter.sol";
import "../src/periphery/libraries/PaimonLibrary.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockWETH.sol";

/// @title PaimonRouter Tests
/// @notice Comprehensive tests for Router liquidity and swap operations
contract PaimonRouterTest is Test {
    PaimonFactory public factory;
    PaimonRouter public router;
    MockWETH public weth;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;

    address public alice;
    uint256 public aliceKey;
    address public bob = address(0x2);

    uint256 constant INITIAL_LIQUIDITY = 100 ether;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        vm.deal(alice, 1000 ether);

        factory = new PaimonFactory(address(this));
        weth = new MockWETH();
        router = new PaimonRouter(address(factory), address(weth));

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        tokenC = new MockERC20("Token C", "TKC", 18);

        // Mint tokens to alice
        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenC.mint(alice, 1000 ether);

        // Approve router
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // ========== Constructor Tests ==========

    function test_Constructor() public view {
        assertEq(router.factory(), address(factory));
        assertEq(router.WETH(), address(weth));
    }

    function test_RevertWhen_Constructor_ZeroFactory() public {
        vm.expectRevert(PaimonRouter.ZeroAddress.selector);
        new PaimonRouter(address(0), address(weth));
    }

    function test_RevertWhen_Constructor_ZeroWETH() public {
        vm.expectRevert(PaimonRouter.ZeroAddress.selector);
        new PaimonRouter(address(factory), address(0));
    }

    // ========== Add Liquidity Tests ==========

    function test_AddLiquidity_CreatesPair() public {
        vm.prank(alice);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertEq(amountA, 10 ether);
        assertEq(amountB, 10 ether);
        assertTrue(liquidity > 0);

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertNotEq(pair, address(0));
    }

    function test_AddLiquidity_ExistingPair() public {
        // First add
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Second add
        vm.prank(alice);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertEq(amountA, 10 ether);
        assertEq(amountB, 10 ether);
        assertTrue(liquidity > 0);
    }

    function test_AddLiquidity_OptimalAmounts() public {
        // Create pool with 1:2 ratio
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            20 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Try to add with different ratio - should optimize
        vm.prank(alice);
        (uint256 amountA, uint256 amountB,) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            30 ether, // More than needed
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Should use optimal B amount (20 for 10 A)
        assertEq(amountA, 10 ether);
        assertEq(amountB, 20 ether);
    }

    function test_RevertWhen_AddLiquidity_Expired() public {
        vm.prank(alice);
        vm.expectRevert(PaimonRouter.Expired.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            alice,
            block.timestamp - 1 // Expired
        );
    }

    function test_RevertWhen_AddLiquidity_InsufficientBAmount() public {
        // Create pool with 1:1 ratio
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // When we provide amountADesired=10, amountBDesired=5 (less than optimal)
        // amountBOptimal = quote(10, 10, 10) = 10 (> amountBDesired=5)
        // So it goes to else branch and calculates amountAOptimal = quote(5, 10, 10) = 5
        // Then checks amountAOptimal >= amountAMin
        // If amountAMin=10 > amountAOptimal=5, revert InsufficientAAmount
        vm.prank(alice);
        vm.expectRevert(PaimonRouter.InsufficientAAmount.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether, // A desired
            5 ether, // B desired (less than optimal of 10)
            10 ether, // A min - too high for optimal calculation
            0, // B min
            alice,
            block.timestamp + 1
        );
    }

    // ========== Add Liquidity ETH Tests ==========

    function test_AddLiquidityETH() public {
        vm.prank(alice);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertEq(amountToken, 10 ether);
        assertEq(amountETH, 10 ether);
        assertTrue(liquidity > 0);
    }

    function test_AddLiquidityETH_RefundsExcess() public {
        // First add liquidity to set ratio
        vm.prank(alice);
        router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            10 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        uint256 balanceBefore = alice.balance;

        // Add with excess ETH
        vm.prank(alice);
        (,uint256 amountETH,) = router.addLiquidityETH{value: 20 ether}(
            address(tokenA),
            10 ether, // Only need 10 ether worth of ETH
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Should refund excess
        assertEq(amountETH, 10 ether);
        assertEq(alice.balance, balanceBefore - 10 ether);
    }

    // ========== Remove Liquidity Tests ==========

    function test_RemoveLiquidity() public {
        // Add liquidity first
        vm.prank(alice);
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));

        // Approve LP tokens
        vm.prank(alice);
        PaimonPair(pair).approve(address(router), liquidity);

        uint256 tokenABefore = tokenA.balanceOf(alice);
        uint256 tokenBBefore = tokenB.balanceOf(alice);

        // Remove liquidity
        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertTrue(amountA > 0);
        assertTrue(amountB > 0);
        assertEq(tokenA.balanceOf(alice), tokenABefore + amountA);
        assertEq(tokenB.balanceOf(alice), tokenBBefore + amountB);
    }

    function test_RevertWhen_RemoveLiquidity_InsufficientAAmount() public {
        // Add liquidity
        vm.prank(alice);
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        vm.prank(alice);
        PaimonPair(pair).approve(address(router), liquidity);

        // Try to remove with too high minimum
        vm.prank(alice);
        vm.expectRevert(PaimonRouter.InsufficientAAmount.selector);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            200 ether, // Too high
            0,
            alice,
            block.timestamp + 1
        );
    }

    // ========== Remove Liquidity ETH Tests ==========

    function test_RemoveLiquidityETH() public {
        // Add liquidity
        vm.prank(alice);
        (,, uint256 liquidity) = router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address pair = factory.getPair(address(tokenA), address(weth));
        vm.prank(alice);
        PaimonPair(pair).approve(address(router), liquidity);

        uint256 ethBefore = alice.balance;
        uint256 tokenBefore = tokenA.balanceOf(alice);

        // Remove liquidity
        vm.prank(alice);
        (uint256 amountToken, uint256 amountETH) = router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertTrue(amountToken > 0);
        assertTrue(amountETH > 0);
        assertEq(alice.balance, ethBefore + amountETH);
        assertEq(tokenA.balanceOf(alice), tokenBefore + amountToken);
    }

    // ========== Remove Liquidity With Permit Tests ==========

    function test_RemoveLiquidityWithPermit() public {
        // Add liquidity
        vm.prank(alice);
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 deadline = block.timestamp + 1;

        // Create permit signature
        bytes32 digest = _getPermitDigest(
            PaimonPair(pair),
            alice,
            address(router),
            liquidity,
            PaimonPair(pair).nonces(alice),
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        // Remove with permit
        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            deadline,
            false,
            v,
            r,
            s
        );

        assertTrue(amountA > 0);
        assertTrue(amountB > 0);
    }

    // ========== Swap Exact Tokens For Tokens Tests ==========

    function test_SwapExactTokensForTokens() public {
        // Setup pool
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountIn = 1 ether;
        uint256[] memory expectedAmounts = router.getAmountsOut(address(factory), amountIn, path);

        uint256 balanceBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(tokenB.balanceOf(alice), balanceBefore + amounts[1]);
    }

    function test_RevertWhen_SwapExactTokensForTokens_InsufficientOutput() public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.prank(alice);
        vm.expectRevert(PaimonRouter.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(
            1 ether,
            100 ether, // Too high minimum
            path,
            alice,
            block.timestamp + 1
        );
    }

    // ========== Swap Tokens For Exact Tokens Tests ==========

    function test_SwapTokensForExactTokens() public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountOut = 1 ether;
        uint256[] memory expectedAmounts = router.getAmountsIn(address(factory), amountOut, path);

        uint256 tokenABefore = tokenA.balanceOf(alice);
        uint256 tokenBBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            10 ether, // Max input
            path,
            alice,
            block.timestamp + 1
        );

        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], amountOut);
        assertEq(tokenA.balanceOf(alice), tokenABefore - amounts[0]);
        assertEq(tokenB.balanceOf(alice), tokenBBefore + amountOut);
    }

    function test_RevertWhen_SwapTokensForExactTokens_ExcessiveInput() public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.prank(alice);
        vm.expectRevert(PaimonRouter.ExcessiveInputAmount.selector);
        router.swapTokensForExactTokens(
            1 ether,
            0.001 ether, // Too low max
            path,
            alice,
            block.timestamp + 1
        );
    }

    // ========== Swap ETH For Tokens Tests ==========

    function test_SwapExactETHForTokens() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 tokenBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amounts = router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(amounts[1] > 0);
        assertEq(tokenA.balanceOf(alice), tokenBefore + amounts[1]);
    }

    function test_RevertWhen_SwapExactETHForTokens_InvalidPath() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA); // Should be WETH
        path[1] = address(tokenB);

        vm.prank(alice);
        vm.expectRevert(PaimonRouter.InvalidPath.selector);
        router.swapExactETHForTokens{value: 1 ether}(0, path, alice, block.timestamp + 1);
    }

    // ========== Swap Tokens For ETH Tests ==========

    function test_SwapExactTokensForETH() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 ethBefore = alice.balance;

        vm.prank(alice);
        uint256[] memory amounts = router.swapExactTokensForETH(
            1 ether,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(amounts[1] > 0);
        assertEq(alice.balance, ethBefore + amounts[1]);
    }

    function test_RevertWhen_SwapExactTokensForETH_InvalidPath() public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB); // Should be WETH

        vm.prank(alice);
        vm.expectRevert(PaimonRouter.InvalidPath.selector);
        router.swapExactTokensForETH(1 ether, 0, path, alice, block.timestamp + 1);
    }

    // ========== Swap ETH For Exact Tokens Tests ==========

    function test_SwapETHForExactTokens() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 amountOut = 1 ether;
        uint256 ethBefore = alice.balance;
        uint256 tokenBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amounts = router.swapETHForExactTokens{value: 10 ether}(
            amountOut,
            path,
            alice,
            block.timestamp + 1
        );

        assertEq(amounts[1], amountOut);
        assertEq(tokenA.balanceOf(alice), tokenBefore + amountOut);
        // Should refund excess ETH
        assertEq(alice.balance, ethBefore - amounts[0]);
    }

    function test_RevertWhen_SwapETHForExactTokens_ExcessiveInput() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        vm.prank(alice);
        vm.expectRevert(PaimonRouter.ExcessiveInputAmount.selector);
        router.swapETHForExactTokens{value: 0.001 ether}(
            1 ether, // Need more ETH than sent
            path,
            alice,
            block.timestamp + 1
        );
    }

    // ========== Multi-Hop Swap Tests ==========

    function test_MultiHopSwap() public {
        // Create A-B and B-C pools
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);
        _addLiquidity(address(tokenB), address(tokenC), 100 ether, 100 ether);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 tokenCBefore = tokenC.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertEq(amounts.length, 3);
        assertTrue(amounts[2] > 0);
        assertEq(tokenC.balanceOf(alice), tokenCBefore + amounts[2]);
    }

    // ========== Fee On Transfer Token Tests ==========

    function test_SwapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 balanceBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1 ether,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(tokenB.balanceOf(alice) > balanceBefore);
    }

    function test_SwapExactETHForTokensSupportingFeeOnTransferTokens() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 balanceBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(tokenA.balanceOf(alice) > balanceBefore);
    }

    function test_SwapExactTokensForETHSupportingFeeOnTransferTokens() public {
        _addLiquidityETH(address(tokenA), 100 ether, 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 ethBefore = alice.balance;

        vm.prank(alice);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1 ether,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(alice.balance > ethBefore);
    }

    // ========== Library Function Tests ==========

    function test_Quote() public view {
        uint256 amountB = router.quote(1 ether, 100 ether, 200 ether);
        assertEq(amountB, 2 ether);
    }

    function test_GetAmountOut() public view {
        uint256 amountOut = router.getAmountOut(1 ether, 100 ether, 100 ether);
        // With 0.3% fee: (1 * 997 * 100) / (100 * 1000 + 1 * 997) = 0.9871...
        assertTrue(amountOut > 0.98 ether);
        assertTrue(amountOut < 1 ether);
    }

    function test_GetAmountIn() public view {
        uint256 amountIn = router.getAmountIn(1 ether, 100 ether, 100 ether);
        // Should need slightly more than 1 ETH due to fee
        assertTrue(amountIn > 1 ether);
    }

    // ========== Receive ETH Tests ==========

    function test_ReceiveETH_OnlyFromWETH() public {
        // Give WETH some ETH first
        vm.deal(address(weth), 10 ether);

        // Should accept from WETH
        vm.prank(address(weth));
        (bool success,) = address(router).call{value: 1 ether}("");
        assertTrue(success);
    }

    function test_RevertWhen_ReceiveETH_NotFromWETH() public {
        // Should reject from other addresses
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        (bool success,) = address(router).call{value: 1 ether}("");
        assertFalse(success);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_AddAndRemoveLiquidity(uint256 amount) public {
        amount = bound(amount, 1 ether, 100 ether);

        vm.startPrank(alice);

        // Add liquidity
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount,
            amount,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        PaimonPair(pair).approve(address(router), liquidity);

        // Remove liquidity
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();

        // Should get back approximately the same (minus minimum liquidity)
        assertTrue(amountA > 0);
        assertTrue(amountB > 0);
    }

    function testFuzz_Swap(uint256 amountIn) public {
        _addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        amountIn = bound(amountIn, 0.001 ether, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 balanceBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        assertTrue(tokenB.balanceOf(alice) > balanceBefore);
    }

    // ========== Helper Functions ==========

    function _addLiquidity(address _tokenA, address _tokenB, uint256 amountA, uint256 amountB) internal {
        vm.prank(alice);
        router.addLiquidity(
            _tokenA,
            _tokenB,
            amountA,
            amountB,
            0,
            0,
            alice,
            block.timestamp + 1
        );
    }

    function _addLiquidityETH(address token, uint256 amountToken, uint256 amountETH) internal {
        vm.prank(alice);
        router.addLiquidityETH{value: amountETH}(
            token,
            amountToken,
            0,
            0,
            alice,
            block.timestamp + 1
        );
    }

    function _getPermitDigest(
        PaimonPair pair,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                pair.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(pair.PERMIT_TYPEHASH(), owner, spender, value, nonce, deadline))
            )
        );
    }
}
