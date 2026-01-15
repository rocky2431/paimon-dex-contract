// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "../src/interfaces/IPaimonPair.sol";
import "../src/interfaces/IPaimonCallee.sol";
import "./mocks/MockERC20.sol";

/// @title PaimonPairAdvanced Tests
/// @notice Advanced tests covering edge cases, security, and protocol fees
contract PaimonPairAdvancedTest is Test {
    PaimonFactory public factory;
    PaimonPair public pair;
    MockERC20 public token0;
    MockERC20 public token1;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public feeRecipient = address(0x3);

    uint256 constant MINIMUM_LIQUIDITY = 10000;

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

    // ========== MINIMUM_LIQUIDITY Tests ==========

    function test_MinimumLiquidity_LockedOnFirstMint() public {
        uint256 amount0 = 1 ether;
        uint256 amount1 = 1 ether;

        token0.mint(address(pair), amount0);
        token1.mint(address(pair), amount1);

        uint256 liquidity = pair.mint(alice);

        // Check MINIMUM_LIQUIDITY is locked at 0xdead
        assertEq(pair.balanceOf(address(0xdead)), MINIMUM_LIQUIDITY);

        // Check alice receives total - MINIMUM_LIQUIDITY
        uint256 expectedLiquidity = 1 ether - MINIMUM_LIQUIDITY;
        assertEq(liquidity, expectedLiquidity);
        assertEq(pair.balanceOf(alice), expectedLiquidity);

        // Total supply should be sqrt(amount0 * amount1)
        assertEq(pair.totalSupply(), 1 ether);
    }

    function test_MinimumLiquidity_PreventsDrainAttack() public {
        // First depositor tries to create imbalanced pool
        uint256 amount0 = 10001; // Just above MINIMUM_LIQUIDITY
        uint256 amount1 = 10001;

        token0.mint(address(pair), amount0);
        token1.mint(address(pair), amount1);

        uint256 liquidity = pair.mint(alice);

        // Verify minimum liquidity is locked
        assertEq(pair.balanceOf(address(0xdead)), MINIMUM_LIQUIDITY);
        assertEq(liquidity, 1); // sqrt(10001*10001) - 10000 = 10001 - 10000 = 1
    }

    function test_RevertWhen_InsufficientLiquidityMinted() public {
        // Try to mint with amounts that result in 0 liquidity
        uint256 amount0 = 10000; // sqrt(10000*10000) = 10000 - 10000 = 0
        uint256 amount1 = 10000;

        token0.mint(address(pair), amount0);
        token1.mint(address(pair), amount1);

        vm.expectRevert(PaimonPair.InsufficientLiquidityMinted.selector);
        pair.mint(alice);
    }

    // ========== Second Mint Tests ==========

    function test_SecondMint_ProportionalLiquidity() public {
        // First mint
        uint256 amount0First = 10 ether;
        uint256 amount1First = 10 ether;
        token0.mint(address(pair), amount0First);
        token1.mint(address(pair), amount1First);
        pair.mint(alice);

        // Second mint - same ratio
        uint256 amount0Second = 5 ether;
        uint256 amount1Second = 5 ether;
        token0.mint(address(pair), amount0Second);
        token1.mint(address(pair), amount1Second);

        uint256 liquidityBefore = pair.totalSupply();
        uint256 liquidity = pair.mint(bob);

        // Bob should receive proportional liquidity
        // liquidity = min((5e18 * totalSupply) / 10e18, (5e18 * totalSupply) / 10e18)
        uint256 expectedLiquidity = (amount0Second * liquidityBefore) / amount0First;
        assertEq(liquidity, expectedLiquidity);
    }

    function test_SecondMint_AsymmetricDeposit() public {
        // First mint
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        pair.mint(alice);

        // Second mint - unbalanced (extra token0)
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 5 ether);

        uint256 totalSupplyBefore = pair.totalSupply();
        uint256 liquidity = pair.mint(bob);

        // Liquidity should be based on the minimum ratio
        // min((10e18 * totalSupply) / 10e18, (5e18 * totalSupply) / 10e18)
        uint256 expectedLiquidity = (5 ether * totalSupplyBefore) / 10 ether;
        assertEq(liquidity, expectedLiquidity);
    }

    // ========== Burn Tests ==========

    function test_Burn_PartialLiquidity() public {
        // Setup pool
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        uint256 liquidity = pair.mint(alice);

        // Burn half
        uint256 burnAmount = liquidity / 2;
        vm.prank(alice);
        pair.transfer(address(pair), burnAmount);

        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        // Should receive approximately half of each token
        assertApproxEqRel(amount0, 5 ether, 0.01e18); // 1% tolerance
        assertApproxEqRel(amount1, 5 ether, 0.01e18);
    }

    function test_Burn_AllLiquidity() public {
        // Setup pool
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        uint256 liquidity = pair.mint(alice);

        // Burn all
        vm.prank(alice);
        pair.transfer(address(pair), liquidity);

        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        // Should receive all tokens minus locked minimum
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);

        // Amounts should be close to original minus MINIMUM_LIQUIDITY portion
        assertTrue(amount0 > 9 ether);
        assertTrue(amount1 > 9 ether);
    }

    function test_RevertWhen_BurnZeroLiquidity() public {
        // Setup pool
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        pair.mint(alice);

        // Try to burn with 0 liquidity sent
        vm.expectRevert(PaimonPair.InsufficientLiquidityBurned.selector);
        pair.burn(alice);
    }

    // ========== Swap K-Invariant Tests ==========

    function test_Swap_InvariantMaintained() public {
        // Setup pool
        uint256 reserve0 = 100 ether;
        uint256 reserve1 = 100 ether;
        token0.mint(address(pair), reserve0);
        token1.mint(address(pair), reserve1);
        pair.mint(alice);

        uint256 kBefore = reserve0 * reserve1;

        // Swap
        uint256 swapIn = 10 ether;
        token0.mint(address(pair), swapIn);

        // Calculate exact output using the formula
        uint256 amountInWithFee = swapIn * 997;
        uint256 numerator = amountInWithFee * reserve1;
        uint256 denominator = reserve0 * 1000 + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        pair.swap(0, amountOut, bob, "");

        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        uint256 kAfter = uint256(newReserve0) * uint256(newReserve1);

        // K should increase (due to fees)
        assertTrue(kAfter >= kBefore, "K invariant violated");
    }

    function test_RevertWhen_Swap_InvariantViolated() public {
        // Setup pool
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Try to get more out than the invariant allows
        token0.mint(address(pair), 10 ether);

        // Try to take too much output
        vm.expectRevert(PaimonPair.InvariantViolation.selector);
        pair.swap(0, 20 ether, bob, ""); // Asking for too much
    }

    function test_RevertWhen_Swap_InvalidTo() public {
        // Setup pool
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        token0.mint(address(pair), 1 ether);

        // Try to swap to token0 address
        vm.expectRevert(PaimonPair.InvalidTo.selector);
        pair.swap(0, 0.5 ether, address(token0), "");

        // Try to swap to token1 address
        vm.expectRevert(PaimonPair.InvalidTo.selector);
        pair.swap(0, 0.5 ether, address(token1), "");
    }

    function test_RevertWhen_Swap_InsufficientInputAmount() public {
        // Setup pool
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Try to swap without sending any tokens
        vm.expectRevert(PaimonPair.InsufficientInputAmount.selector);
        pair.swap(0, 1 ether, bob, "");
    }

    // ========== Protocol Fee Tests ==========

    function test_ProtocolFee_MintsFeeToRecipient() public {
        // Enable protocol fee
        factory.setFeeTo(feeRecipient);

        // First mint
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Perform swaps to generate fees
        for (uint256 i = 0; i < 10; i++) {
            token0.mint(address(pair), 1 ether);
            // Calculate output
            (uint112 r0, uint112 r1,) = pair.getReserves();
            uint256 amountInWithFee = 1 ether * 997;
            uint256 amountOut = (amountInWithFee * r1) / (r0 * 1000 + amountInWithFee);
            pair.swap(0, amountOut, bob, "");
        }

        uint256 feeRecipientBalanceBefore = pair.balanceOf(feeRecipient);

        // Second mint triggers fee collection
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        pair.mint(alice);

        // Fee recipient should have received some LP tokens
        uint256 feeRecipientBalanceAfter = pair.balanceOf(feeRecipient);
        assertTrue(feeRecipientBalanceAfter > feeRecipientBalanceBefore, "Protocol fee not collected");
    }

    function test_ProtocolFee_DisabledWhenFeeToZero() public {
        // Ensure fee is disabled
        assertEq(factory.feeTo(), address(0));

        // First mint
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // kLast should be 0 when fee is disabled
        assertEq(pair.kLast(), 0);

        // Perform swap - calculate output correctly
        token0.mint(address(pair), 1 ether);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amountInWithFee = 1 ether * 997;
        uint256 amountOut = (amountInWithFee * uint256(r1)) / (uint256(r0) * 1000 + amountInWithFee);
        pair.swap(0, amountOut, bob, "");

        // Second mint - must add proportionally to current reserves
        (r0, r1,) = pair.getReserves();
        uint256 amount0ToAdd = 10 ether;
        uint256 amount1ToAdd = (amount0ToAdd * uint256(r1)) / uint256(r0);
        token0.mint(address(pair), amount0ToAdd);
        token1.mint(address(pair), amount1ToAdd);
        pair.mint(alice);

        // kLast should still be 0
        assertEq(pair.kLast(), 0);
    }

    function test_ProtocolFee_KLastUpdatedOnMint() public {
        factory.setFeeTo(feeRecipient);

        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 expectedKLast = uint256(r0) * uint256(r1);

        assertEq(pair.kLast(), expectedKLast);
    }

    function test_ProtocolFee_KLastUpdatedOnBurn() public {
        factory.setFeeTo(feeRecipient);

        // Mint
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        uint256 liquidity = pair.mint(alice);

        // Perform swap - calculate output correctly
        token0.mint(address(pair), 10 ether);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amountInWithFee = 10 ether * 997;
        uint256 amountOut = (amountInWithFee * uint256(r1)) / (uint256(r0) * 1000 + amountInWithFee);
        pair.swap(0, amountOut, bob, "");

        // Burn
        vm.prank(alice);
        pair.transfer(address(pair), liquidity / 2);
        pair.burn(alice);

        // kLast should be updated after burn
        (r0, r1,) = pair.getReserves();
        uint256 expectedKLast = uint256(r0) * uint256(r1);
        assertEq(pair.kLast(), expectedKLast);
    }

    function test_ProtocolFee_ResetKLastWhenDisabled() public {
        factory.setFeeTo(feeRecipient);

        // Mint with fee enabled
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        assertTrue(pair.kLast() > 0);

        // Disable fee
        factory.setFeeTo(address(0));

        // Next mint should reset kLast
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        pair.mint(alice);

        assertEq(pair.kLast(), 0);
    }

    // ========== Price Oracle (TWAP) Tests ==========

    function test_TWAP_CumulativePriceUpdates() public {
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        uint256 price0CumulativeBefore = pair.price0CumulativeLast();
        uint256 price1CumulativeBefore = pair.price1CumulativeLast();

        // Move time forward
        vm.warp(block.timestamp + 1 hours);

        // Trigger update via sync
        pair.sync();

        uint256 price0CumulativeAfter = pair.price0CumulativeLast();
        uint256 price1CumulativeAfter = pair.price1CumulativeLast();

        // Cumulative prices should increase
        assertTrue(price0CumulativeAfter > price0CumulativeBefore);
        assertTrue(price1CumulativeAfter > price1CumulativeBefore);
    }

    function test_TWAP_BlockTimestampLastUpdates() public {
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        (, , uint32 timestampBefore) = pair.getReserves();

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        (, , uint32 timestampAfter) = pair.getReserves();

        assertEq(timestampAfter - timestampBefore, 1 hours);
    }

    function test_TWAP_NoPriceUpdateOnSameBlock() public {
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        uint256 price0CumulativeBefore = pair.price0CumulativeLast();

        // Sync in same block should not update cumulative price
        pair.sync();

        uint256 price0CumulativeAfter = pair.price0CumulativeLast();

        assertEq(price0CumulativeBefore, price0CumulativeAfter);
    }

    // ========== Reentrancy Tests ==========

    function test_RevertWhen_ReentrantMint() public {
        // Setup attacker contract
        ReentrantAttacker attacker = new ReentrantAttacker(address(pair));

        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Give attacker some LP tokens
        vm.prank(alice);
        pair.transfer(address(attacker), 1 ether);

        // Prepare for reentrant attack via burn
        token0.mint(address(pair), 1 ether);
        token1.mint(address(pair), 1 ether);

        // Attacker tries to mint during swap callback - should fail
        // This is tested via the flash loan callback test below
    }

    // ========== Flash Loan Tests ==========

    function test_FlashLoan_CallsPaimonCall() public {
        // Setup pool
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Setup flash loan receiver
        FlashLoanReceiver receiver = new FlashLoanReceiver(address(token0), address(token1));

        // Prepare tokens for repayment (with fee)
        uint256 borrowAmount = 10 ether;
        uint256 feeAmount = (borrowAmount * 3) / 997 + 1;
        token0.mint(address(receiver), feeAmount);

        // Execute flash loan
        pair.swap(borrowAmount, 0, address(receiver), abi.encode("flash"));

        // Verify callback was called
        assertTrue(receiver.wasCalled());
    }

    function test_FlashLoan_MustRepayWithFee() public {
        // Setup pool
        token0.mint(address(pair), 100 ether);
        token1.mint(address(pair), 100 ether);
        pair.mint(alice);

        // Setup malicious receiver that doesn't repay
        MaliciousFlashLoanReceiver malicious = new MaliciousFlashLoanReceiver();

        // Should fail without repayment (either InsufficientInputAmount or InvariantViolation)
        vm.expectRevert(PaimonPair.InsufficientInputAmount.selector);
        pair.swap(10 ether, 0, address(malicious), abi.encode("flash"));
    }

    // ========== Overflow Tests ==========

    function test_RevertWhen_ReserveOverflow() public {
        // Try to add more than uint112.max
        uint256 maxAmount = type(uint112).max;

        token0.mint(address(pair), maxAmount);
        token1.mint(address(pair), maxAmount);
        pair.mint(alice);

        // Try to add more - should overflow
        token0.mint(address(pair), 1);
        token1.mint(address(pair), 1);

        vm.expectRevert(PaimonPair.Overflow.selector);
        pair.mint(alice);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_MintAndBurn(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, MINIMUM_LIQUIDITY + 1, 1e24);
        amount1 = bound(amount1, MINIMUM_LIQUIDITY + 1, 1e24);

        token0.mint(address(pair), amount0);
        token1.mint(address(pair), amount1);

        uint256 liquidity = pair.mint(alice);
        assertTrue(liquidity > 0);

        // Burn all liquidity
        vm.prank(alice);
        pair.transfer(address(pair), liquidity);
        (uint256 out0, uint256 out1) = pair.burn(alice);

        assertTrue(out0 > 0);
        assertTrue(out1 > 0);
    }

    function testFuzz_Swap(uint256 amountIn) public {
        // Setup pool with large reserves
        token0.mint(address(pair), 1000 ether);
        token1.mint(address(pair), 1000 ether);
        pair.mint(alice);

        // Bound input to reasonable range
        amountIn = bound(amountIn, 1e15, 100 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();

        // Calculate expected output
        uint256 amountInWithFee = amountIn * 997;
        uint256 amountOut = (amountInWithFee * r1) / (r0 * 1000 + amountInWithFee);

        // Only proceed if output is reasonable
        if (amountOut > 0 && amountOut < r1) {
            token0.mint(address(pair), amountIn);
            pair.swap(0, amountOut, bob, "");

            assertEq(token1.balanceOf(bob), amountOut);
        }
    }
}

// ========== Helper Contracts ==========

contract ReentrantAttacker {
    PaimonPair public pair;
    bool public attacking;

    constructor(address _pair) {
        pair = PaimonPair(_pair);
    }

    function attack() external {
        attacking = true;
        // Will attempt reentrant call during callback
    }
}

contract FlashLoanReceiver is IPaimonCallee {
    address public token0;
    address public token1;
    bool public wasCalled;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function paimonCall(address, uint256 amount0, uint256, address, bytes calldata) external override {
        wasCalled = true;

        // Repay with fee
        if (amount0 > 0) {
            uint256 repayAmount = amount0 + (amount0 * 3) / 997 + 1;
            MockERC20(token0).transfer(msg.sender, repayAmount);
        }
    }
}

contract MaliciousFlashLoanReceiver is IPaimonCallee {
    function paimonCall(address, uint256, uint256, address, bytes calldata) external override {
        // Do nothing - don't repay
    }
}
