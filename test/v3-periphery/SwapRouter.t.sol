// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SwapRouter} from "../../src/v3-periphery/SwapRouter.sol";
import {ISwapRouter} from "../../src/v3-interfaces/periphery/ISwapRouter.sol";
import {NonfungiblePositionManager} from "../../src/v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "../../src/v3-interfaces/periphery/INonfungiblePositionManager.sol";
import {PaimonV3Factory} from "../../src/v3-core/PaimonV3Factory.sol";
import {PaimonV3Pool} from "../../src/v3-core/PaimonV3Pool.sol";
import {TickMath} from "../../src/v3-core/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract SwapRouterTest is Test {
    PaimonV3Factory public factory;
    NonfungiblePositionManager public nft;
    SwapRouter public router;
    MockWETH public weth;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;

    address public owner = address(this);
    address public lp = address(0x1111);
    address public user = address(0x2222);

    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

    function setUp() public {
        // Deploy factory
        factory = new PaimonV3Factory();

        // Deploy WETH
        weth = new MockWETH();

        // Deploy NFT Position Manager
        nft = new NonfungiblePositionManager(address(factory), address(weth), address(0));

        // Deploy SwapRouter
        router = new SwapRouter(address(factory), address(weth));

        // Deploy tokens and sort them
        MockERC20 tokenA = new MockERC20("Token A", "TKNA");
        MockERC20 tokenB = new MockERC20("Token B", "TKNB");
        MockERC20 tokenC = new MockERC20("Token C", "TKNC");

        // Sort tokens
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        // Simple bubble sort
        for (uint i = 0; i < 2; i++) {
            for (uint j = 0; j < 2 - i; j++) {
                if (tokens[j] > tokens[j + 1]) {
                    (tokens[j], tokens[j + 1]) = (tokens[j + 1], tokens[j]);
                }
            }
        }

        token0 = MockERC20(tokens[0]);
        token1 = MockERC20(tokens[1]);
        token2 = MockERC20(tokens[2]);

        // Setup liquidity provider
        token0.mint(lp, 10000 ether);
        token1.mint(lp, 10000 ether);
        token2.mint(lp, 10000 ether);

        // Setup user
        token0.mint(user, 1000 ether);
        token1.mint(user, 1000 ether);
        token2.mint(user, 1000 ether);

        // Create pools and add liquidity
        _setupPool(address(token0), address(token1));
        _setupPool(address(token1), address(token2));
    }

    function _setupPool(address tokenA, address tokenB) internal {
        // Create and initialize pool
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price

        vm.prank(lp);
        nft.createAndInitializePoolIfNecessary(tokenA, tokenB, FEE, sqrtPriceX96);

        // Add liquidity
        vm.startPrank(lp);
        IERC20(tokenA).approve(address(nft), type(uint256).max);
        IERC20(tokenB).approve(address(nft), type(uint256).max);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: tokenA,
            token1: tokenB,
            fee: FEE,
            tickLower: -TICK_SPACING * 100,
            tickUpper: TICK_SPACING * 100,
            amount0Desired: 1000 ether,
            amount1Desired: 1000 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: lp,
            deadline: block.timestamp + 1 hours
        });

        nft.mint(params);
        vm.stopPrank();
    }

    function test_ExactInputSingle() public {
        uint256 amountIn = 1 ether;

        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        uint256 balanceBefore = token1.balanceOf(user);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: FEE,
            recipient: user,
            deadline: block.timestamp + 1 hours,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = router.exactInputSingle(params);
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertEq(token1.balanceOf(user), balanceBefore + amountOut);
    }

    function test_ExactInput_MultiHop() public {
        uint256 amountIn = 1 ether;

        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        uint256 balanceBefore = token2.balanceOf(user);

        // Path: token0 -> token1 -> token2
        bytes memory path = abi.encodePacked(address(token0), FEE, address(token1), FEE, address(token2));

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: user,
            deadline: block.timestamp + 1 hours,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        uint256 amountOut = router.exactInput(params);
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertEq(token2.balanceOf(user), balanceBefore + amountOut);
    }

    function test_ExactOutputSingle() public {
        uint256 amountOut = 0.5 ether;

        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        uint256 balance0Before = token0.balanceOf(user);
        uint256 balance1Before = token1.balanceOf(user);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: FEE,
            recipient: user,
            deadline: block.timestamp + 1 hours,
            amountOut: amountOut,
            amountInMaximum: 10 ether,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = router.exactOutputSingle(params);
        vm.stopPrank();

        assertGt(amountIn, 0);
        assertEq(token1.balanceOf(user), balance1Before + amountOut);
        assertEq(token0.balanceOf(user), balance0Before - amountIn);
    }

    function test_ExactOutput_MultiHop() public {
        uint256 amountOut = 0.5 ether;

        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        uint256 balance0Before = token0.balanceOf(user);
        uint256 balance2Before = token2.balanceOf(user);

        // Path for exact output is reversed: token2 -> token1 -> token0
        bytes memory path = abi.encodePacked(address(token2), FEE, address(token1), FEE, address(token0));

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: user,
            deadline: block.timestamp + 1 hours,
            amountOut: amountOut,
            amountInMaximum: 10 ether
        });

        uint256 amountIn = router.exactOutput(params);
        vm.stopPrank();

        assertGt(amountIn, 0);
        assertEq(token2.balanceOf(user), balance2Before + amountOut);
        assertEq(token0.balanceOf(user), balance0Before - amountIn);
    }

    function test_RevertWhen_DeadlineExpired() public {
        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: FEE,
            recipient: user,
            deadline: block.timestamp - 1, // Expired
            amountIn: 1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.expectRevert();
        router.exactInputSingle(params);
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientOutput() public {
        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: FEE,
            recipient: user,
            deadline: block.timestamp + 1 hours,
            amountIn: 1 ether,
            amountOutMinimum: 100 ether, // Unrealistic minimum
            sqrtPriceLimitX96: 0
        });

        vm.expectRevert();
        router.exactInputSingle(params);
        vm.stopPrank();
    }
}
