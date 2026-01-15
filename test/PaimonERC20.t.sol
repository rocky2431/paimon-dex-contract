// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PaimonFactory.sol";
import "../src/core/PaimonPair.sol";
import "../src/core/PaimonERC20.sol";
import "./mocks/MockERC20.sol";

contract PaimonERC20Test is Test {
    PaimonFactory public factory;
    PaimonPair public pair;
    MockERC20 public token0;
    MockERC20 public token1;

    address public alice;
    uint256 public aliceKey;
    address public bob = address(0x2);

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");

        factory = new PaimonFactory(address(this));

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);

        address pairAddr = factory.createPair(address(tokenA), address(tokenB));
        pair = PaimonPair(pairAddr);

        (token0, token1) = address(tokenA) < address(tokenB)
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // Mint some LP tokens to alice for testing
        token0.mint(address(pair), 10 ether);
        token1.mint(address(pair), 10 ether);
        pair.mint(alice);
    }

    // ========== ERC20 Basic Tests ==========

    function test_Name() public view {
        assertEq(pair.name(), "Paimon LP");
    }

    function test_Symbol() public view {
        assertEq(pair.symbol(), "PAIMON-LP");
    }

    function test_Decimals() public view {
        assertEq(pair.decimals(), 18);
    }

    function test_Transfer() public {
        uint256 amount = 1 ether;
        uint256 aliceBalanceBefore = pair.balanceOf(alice);

        vm.prank(alice);
        pair.transfer(bob, amount);

        assertEq(pair.balanceOf(alice), aliceBalanceBefore - amount);
        assertEq(pair.balanceOf(bob), amount);
    }

    function test_Transfer_EmitsEvent() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, amount);

        vm.prank(alice);
        pair.transfer(bob, amount);
    }

    function test_Approve() public {
        uint256 amount = 1 ether;

        vm.prank(alice);
        bool success = pair.approve(bob, amount);

        assertTrue(success);
        assertEq(pair.allowance(alice, bob), amount);
    }

    function test_Approve_EmitsEvent() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, amount);

        vm.prank(alice);
        pair.approve(bob, amount);
    }

    function test_TransferFrom() public {
        uint256 amount = 1 ether;

        vm.prank(alice);
        pair.approve(bob, amount);

        uint256 aliceBalanceBefore = pair.balanceOf(alice);
        address charlie = address(0x3);

        vm.prank(bob);
        pair.transferFrom(alice, charlie, amount);

        assertEq(pair.balanceOf(alice), aliceBalanceBefore - amount);
        assertEq(pair.balanceOf(charlie), amount);
        assertEq(pair.allowance(alice, bob), 0);
    }

    function test_TransferFrom_MaxApproval() public {
        uint256 amount = 1 ether;

        vm.prank(alice);
        pair.approve(bob, type(uint256).max);

        vm.prank(bob);
        pair.transferFrom(alice, bob, amount);

        // Max approval should not decrease
        assertEq(pair.allowance(alice, bob), type(uint256).max);
    }

    function test_RevertWhen_TransferInsufficientBalance() public {
        uint256 balance = pair.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();
        pair.transfer(bob, balance + 1);
    }

    function test_RevertWhen_TransferFromInsufficientAllowance() public {
        vm.prank(alice);
        pair.approve(bob, 1 ether);

        vm.prank(bob);
        vm.expectRevert();
        pair.transferFrom(alice, bob, 2 ether);
    }

    // ========== EIP-2612 Permit Tests ==========

    function test_DomainSeparator() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Paimon LP")),
                keccak256(bytes("1")),
                block.chainid,
                address(pair)
            )
        );
        assertEq(pair.DOMAIN_SEPARATOR(), expected);
    }

    function test_Permit() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonceBefore = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        pair.permit(alice, bob, value, deadline, v, r, s);

        assertEq(pair.allowance(alice, bob), value);
        assertEq(pair.nonces(alice), nonceBefore + 1);
    }

    function test_Permit_MaxValue() public {
        uint256 value = type(uint256).max;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        pair.permit(alice, bob, value, deadline, v, r, s);

        assertEq(pair.allowance(alice, bob), type(uint256).max);
    }

    function test_RevertWhen_Permit_Expired() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp - 1; // Already expired
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        vm.expectRevert(PaimonERC20.Expired.selector);
        pair.permit(alice, bob, value, deadline, v, r, s);
    }

    function test_RevertWhen_Permit_InvalidSignature() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);

        // Sign with wrong key
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        vm.expectRevert(PaimonERC20.InvalidSignature.selector);
        pair.permit(alice, bob, value, deadline, v, r, s);
    }

    function test_RevertWhen_Permit_ZeroOwner() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Try to permit with owner as zero address
        vm.expectRevert(PaimonERC20.ZeroAddress.selector);
        pair.permit(address(0), bob, value, deadline, 27, bytes32(0), bytes32(0));
    }

    function test_RevertWhen_Permit_ZeroSpender() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, address(0), value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        // Try to permit with spender as zero address
        vm.expectRevert(PaimonERC20.ZeroAddress.selector);
        pair.permit(alice, address(0), value, deadline, v, r, s);
    }

    function test_RevertWhen_Permit_ReplayAttack() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        // First permit should succeed
        pair.permit(alice, bob, value, deadline, v, r, s);

        // Replay should fail (nonce increased)
        vm.expectRevert(PaimonERC20.InvalidSignature.selector);
        pair.permit(alice, bob, value, deadline, v, r, s);
    }

    function test_Permit_NonceIncrement() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;

        for (uint256 i = 0; i < 3; i++) {
            uint256 nonce = pair.nonces(alice);
            assertEq(nonce, i);

            bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

            pair.permit(alice, bob, value, deadline, v, r, s);
        }

        assertEq(pair.nonces(alice), 3);
    }

    function test_Permit_ThenTransferFrom() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        pair.permit(alice, bob, value, deadline, v, r, s);

        uint256 aliceBalanceBefore = pair.balanceOf(alice);

        vm.prank(bob);
        pair.transferFrom(alice, bob, value);

        assertEq(pair.balanceOf(alice), aliceBalanceBefore - value);
        assertEq(pair.balanceOf(bob), value);
    }

    // ========== Chain Fork Protection Test ==========

    function test_DomainSeparator_ChainForkProtection() public {
        bytes32 originalDS = pair.DOMAIN_SEPARATOR();

        // Simulate chain fork by changing chain ID
        vm.chainId(999);

        bytes32 newDS = pair.DOMAIN_SEPARATOR();

        // Domain separator should be different on different chain
        assertNotEq(originalDS, newDS);

        // Verify it's correctly computed for new chain
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Paimon LP")),
                keccak256(bytes("1")),
                999,
                address(pair)
            )
        );
        assertEq(newDS, expected);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_Transfer(uint256 amount) public {
        uint256 balance = pair.balanceOf(alice);
        amount = bound(amount, 0, balance);

        vm.prank(alice);
        pair.transfer(bob, amount);

        assertEq(pair.balanceOf(alice), balance - amount);
        assertEq(pair.balanceOf(bob), amount);
    }

    function testFuzz_Permit(uint256 value, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        uint256 nonce = pair.nonces(alice);

        bytes32 digest = _getPermitDigest(alice, bob, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        pair.permit(alice, bob, value, deadline, v, r, s);

        assertEq(pair.allowance(alice, bob), value);
    }

    // ========== Helper Functions ==========

    function _getPermitDigest(
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

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
