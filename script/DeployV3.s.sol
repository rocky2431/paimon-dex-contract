// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PaimonV3Factory} from "../src/v3-core/PaimonV3Factory.sol";
import {NonfungiblePositionManager} from "../src/v3-periphery/NonfungiblePositionManager.sol";
import {SwapRouter} from "../src/v3-periphery/SwapRouter.sol";
import {Quoter} from "../src/v3-periphery/Quoter.sol";
import {QuoterV2} from "../src/v3-periphery/QuoterV2.sol";
import {TickLens} from "../src/v3-periphery/TickLens.sol";

/// @title Deploy Paimon V3 Contracts
/// @notice Deploys the full Paimon V3 stack
contract DeployV3 is Script {
    // BSC Mainnet WBNB
    address constant WBNB_MAINNET = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // BSC Testnet WBNB
    address constant WBNB_TESTNET = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    struct DeploymentResult {
        address factory;
        address nftPositionManager;
        address swapRouter;
        address quoter;
        address quoterV2;
        address tickLens;
    }

    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address weth = _getWETH();

        console.log("Deploying Paimon V3 contracts...");
        console.log("WETH/WBNB address:", weth);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy core contracts
        PaimonV3Factory factory = new PaimonV3Factory();
        console.log("PaimonV3Factory deployed at:", address(factory));

        // Deploy periphery contracts
        NonfungiblePositionManager nftPositionManager = new NonfungiblePositionManager(
            address(factory),
            weth,
            address(0) // Token descriptor (optional)
        );
        console.log("NonfungiblePositionManager deployed at:", address(nftPositionManager));

        SwapRouter swapRouter = new SwapRouter(address(factory), weth);
        console.log("SwapRouter deployed at:", address(swapRouter));

        Quoter quoter = new Quoter(address(factory), weth);
        console.log("Quoter deployed at:", address(quoter));

        QuoterV2 quoterV2 = new QuoterV2(address(factory), weth);
        console.log("QuoterV2 deployed at:", address(quoterV2));

        TickLens tickLens = new TickLens();
        console.log("TickLens deployed at:", address(tickLens));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Factory:", address(factory));
        console.log("NFT Position Manager:", address(nftPositionManager));
        console.log("Swap Router:", address(swapRouter));
        console.log("Quoter:", address(quoter));
        console.log("QuoterV2:", address(quoterV2));
        console.log("TickLens:", address(tickLens));
        console.log("");
        console.log("Default fee tiers enabled:");
        console.log("  - 500 (0.05%) with tick spacing 10");
        console.log("  - 3000 (0.3%) with tick spacing 60");
        console.log("  - 10000 (1%) with tick spacing 200");

        return DeploymentResult({
            factory: address(factory),
            nftPositionManager: address(nftPositionManager),
            swapRouter: address(swapRouter),
            quoter: address(quoter),
            quoterV2: address(quoterV2),
            tickLens: address(tickLens)
        });
    }

    function _getWETH() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 56) {
            // BSC Mainnet
            return WBNB_MAINNET;
        } else if (chainId == 97) {
            // BSC Testnet
            return WBNB_TESTNET;
        } else if (chainId == 31337) {
            // Anvil/Hardhat local
            // In local testing, you might want to deploy a mock WETH
            revert("Local network: Please set WETH address manually or deploy MockWETH");
        } else {
            revert("Unsupported network");
        }
    }
}

/// @title Deploy Paimon V3 to Local Network
/// @notice For local testing with mock WETH
contract DeployV3Local is Script {
    function run() external {
        // Deploy mock WETH first
        vm.startBroadcast();

        // Deploy MockWETH
        MockWETH weth = new MockWETH();
        console.log("MockWETH deployed at:", address(weth));

        // Deploy V3 contracts
        PaimonV3Factory factory = new PaimonV3Factory();
        console.log("PaimonV3Factory deployed at:", address(factory));

        NonfungiblePositionManager nftPositionManager = new NonfungiblePositionManager(
            address(factory),
            address(weth),
            address(0)
        );
        console.log("NonfungiblePositionManager deployed at:", address(nftPositionManager));

        SwapRouter swapRouter = new SwapRouter(address(factory), address(weth));
        console.log("SwapRouter deployed at:", address(swapRouter));

        Quoter quoter = new Quoter(address(factory), address(weth));
        console.log("Quoter deployed at:", address(quoter));

        QuoterV2 quoterV2 = new QuoterV2(address(factory), address(weth));
        console.log("QuoterV2 deployed at:", address(quoterV2));

        TickLens tickLens = new TickLens();
        console.log("TickLens deployed at:", address(tickLens));

        vm.stopBroadcast();
    }
}

/// @title Mock WETH for local testing
contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
    event Approval(address indexed src, address indexed guy, uint wad);

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}
