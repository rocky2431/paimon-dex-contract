// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
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

contract NonfungiblePositionManagerTest is Test {
    PaimonV3Factory public factory;
    NonfungiblePositionManager public nft;
    MockWETH public weth;
    MockERC20 public token0;
    MockERC20 public token1;

    address public owner = address(this);
    address public user = address(0x1234);

    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

    function setUp() public {
        // Deploy factory
        factory = new PaimonV3Factory();

        // Deploy WETH
        weth = new MockWETH();

        // Deploy NFT Position Manager
        nft = new NonfungiblePositionManager(address(factory), address(weth), address(0));

        // Deploy tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA");
        MockERC20 tokenB = new MockERC20("Token B", "TKNB");

        // Sort tokens
        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        // Mint tokens to user
        token0.mint(user, 1000 ether);
        token1.mint(user, 1000 ether);
    }

    function test_CreateAndInitializePool() public {
        // Calculate initial price (1:1)
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96

        vm.prank(user);
        address pool = nft.createAndInitializePoolIfNecessary(
            address(token0),
            address(token1),
            FEE,
            sqrtPriceX96
        );

        assertTrue(pool != address(0));
        assertEq(factory.getPool(address(token0), address(token1), FEE), pool);
    }

    function test_Mint() public {
        // Create pool
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        vm.prank(user);
        address pool = nft.createAndInitializePoolIfNecessary(
            address(token0),
            address(token1),
            FEE,
            sqrtPriceX96
        );

        // Approve tokens
        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        // Mint position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: -TICK_SPACING * 10,
            tickUpper: TICK_SPACING * 10,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nft.mint(params);
        vm.stopPrank();

        assertGt(tokenId, 0);
        assertGt(liquidity, 0);
        assertGt(amount0, 0);
        assertGt(amount1, 0);

        // Check NFT ownership
        assertEq(nft.ownerOf(tokenId), user);
    }

    function test_IncreaseLiquidity() public {
        // Setup: Create pool and mint position
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        vm.prank(user);
        nft.createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, sqrtPriceX96);

        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: -TICK_SPACING * 10,
            tickUpper: TICK_SPACING * 10,
            amount0Desired: 50 ether,
            amount1Desired: 50 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 initialLiquidity, , ) = nft.mint(mintParams);

        // Increase liquidity
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 50 ether,
                amount1Desired: 50 ether,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            });

        (uint128 addedLiquidity, , ) = nft.increaseLiquidity(increaseParams);
        vm.stopPrank();

        assertGt(addedLiquidity, 0);

        // Check position liquidity increased
        (, , , , , , , uint128 newLiquidity, , , , ) = nft.positions(tokenId);
        assertEq(newLiquidity, initialLiquidity + addedLiquidity);
    }

    function test_DecreaseLiquidity() public {
        // Setup: Create pool and mint position
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        vm.prank(user);
        nft.createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, sqrtPriceX96);

        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: -TICK_SPACING * 10,
            tickUpper: TICK_SPACING * 10,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 initialLiquidity, , ) = nft.mint(mintParams);

        // Decrease half liquidity
        uint128 liquidityToRemove = initialLiquidity / 2;
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            });

        (uint256 amount0, uint256 amount1) = nft.decreaseLiquidity(decreaseParams);
        vm.stopPrank();

        assertGt(amount0, 0);
        assertGt(amount1, 0);

        // Check position liquidity decreased
        (, , , , , , , uint128 newLiquidity, , , , ) = nft.positions(tokenId);
        assertEq(newLiquidity, initialLiquidity - liquidityToRemove);
    }

    function test_Collect() public {
        // Setup: Create pool and mint position
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        vm.prank(user);
        nft.createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, sqrtPriceX96);

        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: -TICK_SPACING * 10,
            tickUpper: TICK_SPACING * 10,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 initialLiquidity, , ) = nft.mint(mintParams);

        // Decrease all liquidity to generate tokens owed
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: initialLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            });

        nft.decreaseLiquidity(decreaseParams);

        // Collect tokens
        uint256 balanceBefore0 = token0.balanceOf(user);
        uint256 balanceBefore1 = token1.balanceOf(user);

        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: user,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 collected0, uint256 collected1) = nft.collect(collectParams);
        vm.stopPrank();

        assertGt(collected0, 0);
        assertGt(collected1, 0);
        assertEq(token0.balanceOf(user), balanceBefore0 + collected0);
        assertEq(token1.balanceOf(user), balanceBefore1 + collected1);
    }

    function test_Burn() public {
        // Setup: Create pool and mint position
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        vm.prank(user);
        nft.createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, sqrtPriceX96);

        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: -TICK_SPACING * 10,
            tickUpper: TICK_SPACING * 10,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 liquidity, , ) = nft.mint(mintParams);

        // Decrease all liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            });
        nft.decreaseLiquidity(decreaseParams);

        // Collect all tokens
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: user,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        nft.collect(collectParams);

        // Burn the position
        nft.burn(tokenId);
        vm.stopPrank();

        // Check NFT is burned
        vm.expectRevert();
        nft.ownerOf(tokenId);
    }

    function test_Positions() public {
        // Setup: Create pool and mint position
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        vm.prank(user);
        nft.createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, sqrtPriceX96);

        vm.startPrank(user);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);

        int24 tickLower = -TICK_SPACING * 10;
        int24 tickUpper = TICK_SPACING * 10;

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId, uint128 liquidity, , ) = nft.mint(mintParams);
        vm.stopPrank();

        // Check position data
        (
            uint96 nonce,
            address operator,
            address _token0,
            address _token1,
            uint24 fee,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = nft.positions(tokenId);

        assertEq(nonce, 0);
        assertEq(operator, address(0));
        assertEq(_token0, address(token0));
        assertEq(_token1, address(token1));
        assertEq(fee, FEE);
        assertEq(_tickLower, tickLower);
        assertEq(_tickUpper, tickUpper);
        assertEq(_liquidity, liquidity);
    }
}
