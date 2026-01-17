// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PaimonV3Factory} from "../../src/v3-core/PaimonV3Factory.sol";
import {PaimonV3Pool} from "../../src/v3-core/PaimonV3Pool.sol";
import {TickMath} from "../../src/v3-core/libraries/TickMath.sol";
import {IPaimonV3MintCallback} from "../../src/v3-interfaces/callback/IPaimonV3MintCallback.sol";
import {IPaimonV3SwapCallback} from "../../src/v3-interfaces/callback/IPaimonV3SwapCallback.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestMintCallback is IPaimonV3MintCallback {
    function paimonV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        (address token0, address token1, address payer) = abi.decode(data, (address, address, address));
        if (amount0Owed > 0) {
            MockERC20(token0).transferFrom(payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            MockERC20(token1).transferFrom(payer, msg.sender, amount1Owed);
        }
    }
}

contract TestSwapCallback is IPaimonV3SwapCallback {
    function paimonV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        (address token0, address token1, address payer) = abi.decode(data, (address, address, address));
        if (amount0Delta > 0) {
            MockERC20(token0).transferFrom(payer, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            MockERC20(token1).transferFrom(payer, msg.sender, uint256(amount1Delta));
        }
    }
}

contract PaimonV3PoolTest is Test {
    PaimonV3Factory public factory;
    PaimonV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    TestMintCallback public mintCallback;
    TestSwapCallback public swapCallback;

    address public owner = address(this);
    address public user1 = address(0x1);

    uint160 constant INIT_PRICE = 79228162514264337593543950336; // 1:1 price (sqrt(1) * 2^96)

    function setUp() public {
        factory = new PaimonV3Factory();

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);

        // Ensure token0 < token1
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Create pool
        address poolAddr = factory.createPool(address(token0), address(token1), 3000);
        pool = PaimonV3Pool(poolAddr);

        // Deploy callbacks
        mintCallback = new TestMintCallback();
        swapCallback = new TestSwapCallback();

        // Mint tokens
        token0.mint(owner, 1000000e18);
        token1.mint(owner, 1000000e18);

        // Approve callbacks
        token0.approve(address(mintCallback), type(uint256).max);
        token1.approve(address(mintCallback), type(uint256).max);
        token0.approve(address(swapCallback), type(uint256).max);
        token1.approve(address(swapCallback), type(uint256).max);
    }

    // Initialize tests

    function test_Initialize_Success() public {
        pool.initialize(INIT_PRICE);

        (uint160 sqrtPriceX96, int24 tick, , , , , bool unlocked) = pool.slot0();

        assertEq(sqrtPriceX96, INIT_PRICE);
        assertEq(tick, 0);
        assertTrue(unlocked);
    }

    function test_Initialize_RevertsIfAlreadyInitialized() public {
        pool.initialize(INIT_PRICE);

        vm.expectRevert(PaimonV3Pool.AlreadyInitialized.selector);
        pool.initialize(INIT_PRICE);
    }

    // Mint tests

    function test_Mint_Success() public {
        pool.initialize(INIT_PRICE);

        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint128 amount = 1e18;

        vm.prank(address(mintCallback));
        (uint256 amount0, uint256 amount1) = pool.mint(
            owner,
            tickLower,
            tickUpper,
            amount,
            abi.encode(address(token0), address(token1), owner)
        );

        assertTrue(amount0 > 0 || amount1 > 0);
        assertEq(pool.liquidity(), amount);
    }

    function test_Mint_RevertsIfNotInitialized() public {
        vm.expectRevert(PaimonV3Pool.Locked.selector);
        pool.mint(owner, -60, 60, 1e18, "");
    }

    function test_Mint_RevertsForZeroLiquidity() public {
        pool.initialize(INIT_PRICE);

        vm.prank(address(mintCallback));
        vm.expectRevert(PaimonV3Pool.InsufficientLiquidity.selector);
        pool.mint(owner, -60, 60, 0, "");
    }

    function test_Mint_RevertsForInvalidTicks() public {
        pool.initialize(INIT_PRICE);

        // tickLower >= tickUpper
        vm.prank(address(mintCallback));
        vm.expectRevert(PaimonV3Pool.InvalidTick.selector);
        pool.mint(owner, 60, 60, 1e18, "");

        // tickLower >= tickUpper
        vm.prank(address(mintCallback));
        vm.expectRevert(PaimonV3Pool.InvalidTick.selector);
        pool.mint(owner, 120, 60, 1e18, "");
    }

    // Burn tests

    function test_Burn_Success() public {
        pool.initialize(INIT_PRICE);

        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint128 amount = 1e18;

        // First mint
        vm.prank(address(mintCallback));
        pool.mint(owner, tickLower, tickUpper, amount, abi.encode(address(token0), address(token1), owner));

        // Then burn
        (uint256 amount0, uint256 amount1) = pool.burn(tickLower, tickUpper, amount);

        assertTrue(amount0 > 0 || amount1 > 0);
        assertEq(pool.liquidity(), 0);
    }

    // Swap tests

    function test_Swap_ZeroForOne() public {
        pool.initialize(INIT_PRICE);

        // Add liquidity first
        int24 tickLower = -600;
        int24 tickUpper = 600;
        uint128 liquidityAmount = 10e18;

        vm.prank(address(mintCallback));
        pool.mint(owner, tickLower, tickUpper, liquidityAmount, abi.encode(address(token0), address(token1), owner));

        // Perform swap
        int256 amountSpecified = 1e18; // exact input of 1 token0

        vm.prank(address(swapCallback));
        (int256 amount0, int256 amount1) = pool.swap(
            user1,
            true, // zeroForOne
            amountSpecified,
            TickMath.MIN_SQRT_RATIO + 1,
            abi.encode(address(token0), address(token1), owner)
        );

        // amount0 should be positive (we're spending token0)
        assertTrue(amount0 > 0);
        // amount1 should be negative (we're receiving token1)
        assertTrue(amount1 < 0);
    }

    function test_Swap_OneForZero() public {
        pool.initialize(INIT_PRICE);

        // Add liquidity first
        int24 tickLower = -600;
        int24 tickUpper = 600;
        uint128 liquidityAmount = 10e18;

        vm.prank(address(mintCallback));
        pool.mint(owner, tickLower, tickUpper, liquidityAmount, abi.encode(address(token0), address(token1), owner));

        // Perform swap
        int256 amountSpecified = 1e18; // exact input of 1 token1

        vm.prank(address(swapCallback));
        (int256 amount0, int256 amount1) = pool.swap(
            user1,
            false, // oneForZero
            amountSpecified,
            TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(address(token0), address(token1), owner)
        );

        // amount0 should be negative (we're receiving token0)
        assertTrue(amount0 < 0);
        // amount1 should be positive (we're spending token1)
        assertTrue(amount1 > 0);
    }

    function test_Swap_RevertsForZeroAmount() public {
        pool.initialize(INIT_PRICE);

        vm.prank(address(swapCallback));
        vm.expectRevert(PaimonV3Pool.InsufficientInputAmount.selector);
        pool.swap(user1, true, 0, TickMath.MIN_SQRT_RATIO + 1, "");
    }

    // Collect tests

    function test_Collect_Success() public {
        pool.initialize(INIT_PRICE);

        int24 tickLower = -600;
        int24 tickUpper = 600;
        uint128 liquidityAmount = 10e18;

        // Mint liquidity
        vm.prank(address(mintCallback));
        pool.mint(owner, tickLower, tickUpper, liquidityAmount, abi.encode(address(token0), address(token1), owner));

        // Perform swap to generate fees
        int256 swapAmount = 1e18;
        vm.prank(address(swapCallback));
        pool.swap(
            user1,
            true,
            swapAmount,
            TickMath.MIN_SQRT_RATIO + 1,
            abi.encode(address(token0), address(token1), owner)
        );

        // Burn 0 liquidity to update position fees
        pool.burn(tickLower, tickUpper, 0);

        // Collect fees
        (uint128 collected0, uint128 collected1) = pool.collect(
            owner,
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );

        // Should have collected some fees
        assertTrue(collected0 > 0 || collected1 > 0);
    }

    // Protocol fee tests

    function test_SetFeeProtocol_Success() public {
        pool.initialize(INIT_PRICE);

        pool.setFeeProtocol(4, 4);

        (, , , , , uint8 feeProtocol, ) = pool.slot0();
        assertEq(feeProtocol, 4 + (4 << 4));
    }

    function test_SetFeeProtocol_RevertsForNonOwner() public {
        pool.initialize(INIT_PRICE);

        vm.prank(user1);
        vm.expectRevert(PaimonV3Pool.NotOwner.selector);
        pool.setFeeProtocol(4, 4);
    }

    function test_SetFeeProtocol_RevertsForInvalidValue() public {
        pool.initialize(INIT_PRICE);

        vm.expectRevert(PaimonV3Pool.InvalidFeeProtocol.selector);
        pool.setFeeProtocol(3, 4); // 3 is invalid (must be 0 or 4-10)

        vm.expectRevert(PaimonV3Pool.InvalidFeeProtocol.selector);
        pool.setFeeProtocol(4, 11); // 11 is invalid
    }

    // Observation tests

    function test_IncreaseObservationCardinality() public {
        pool.initialize(INIT_PRICE);

        pool.increaseObservationCardinalityNext(10);

        (, , , , uint16 observationCardinalityNext, , ) = pool.slot0();
        assertEq(observationCardinalityNext, 10);
    }

    function test_Observe_CurrentTime() public {
        pool.initialize(INIT_PRICE);

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        // At initialization, tick cumulative is 0
        assertEq(tickCumulatives[0], 0);
    }
}
