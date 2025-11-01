// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/USDStablecoin.sol";

contract USDStablecoinTest is Test {
    USDStablecoin public usdt;
    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        usdt = new USDStablecoin();
    }

    function testDeployment() public view {
        assertEq(usdt.name(), "Tether USD");
        assertEq(usdt.symbol(), "USDT");
        assertEq(usdt.decimals(), 18);
        assertEq(usdt.totalSupply(), 0);
    }

    function testMint() public {
        uint256 amount = 1000e18;

        usdt.mint(alice, amount);

        assertEq(usdt.balanceOf(alice), amount);
        assertEq(usdt.totalSupply(), amount);
    }

    function testMintToMultipleAddresses() public {
        uint256 aliceAmount = 500e18;
        uint256 bobAmount = 1000e18;

        usdt.mint(alice, aliceAmount);
        usdt.mint(bob, bobAmount);

        assertEq(usdt.balanceOf(alice), aliceAmount);
        assertEq(usdt.balanceOf(bob), bobAmount);
        assertEq(usdt.totalSupply(), aliceAmount + bobAmount);
    }

    function testPreMint() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = makeAddr("charlie");

        uint256 amount = 1000e18;

        usdt.preMint(recipients, amount);

        assertEq(usdt.balanceOf(alice), amount);
        assertEq(usdt.balanceOf(bob), amount);
        assertEq(usdt.balanceOf(recipients[2]), amount);
        assertEq(usdt.totalSupply(), amount * 3);
    }

    function testPreMintOnlyOwner() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        // Switch to non-owner
        vm.prank(bob);

        vm.expectRevert();
        usdt.preMint(recipients, 1000e18);
    }

    function testTransfer() public {
        uint256 amount = 1000e18;
        usdt.mint(alice, amount);

        vm.prank(alice);
        usdt.transfer(bob, 300e18);

        assertEq(usdt.balanceOf(alice), 700e18);
        assertEq(usdt.balanceOf(bob), 300e18);
    }

    function testApproveAndTransferFrom() public {
        uint256 amount = 1000e18;
        usdt.mint(alice, amount);

        vm.prank(alice);
        usdt.approve(bob, 500e18);

        assertEq(usdt.allowance(alice, bob), 500e18);

        vm.prank(bob);
        usdt.transferFrom(alice, bob, 300e18);

        assertEq(usdt.balanceOf(alice), 700e18);
        assertEq(usdt.balanceOf(bob), 300e18);
        assertEq(usdt.allowance(alice, bob), 200e18);
    }

    // Fuzz test for minting
    function testFuzzMint(address to, uint96 amount) public {
        vm.assume(to != address(0));

        usdt.mint(to, amount);

        assertEq(usdt.balanceOf(to), amount);
        assertEq(usdt.totalSupply(), amount);
    }

    // Fuzz test for pre-mint
    function testFuzzPreMint(uint8 recipientCount, uint96 amount) public {
        vm.assume(recipientCount > 0 && recipientCount <= 50); // Reasonable limit

        address[] memory recipients = new address[](recipientCount);
        for (uint256 i = 0; i < recipientCount; i++) {
            recipients[i] = address(uint160(i + 1)); // Non-zero addresses
        }

        usdt.preMint(recipients, amount);

        for (uint256 i = 0; i < recipientCount; i++) {
            assertEq(usdt.balanceOf(recipients[i]), amount);
        }
        assertEq(usdt.totalSupply(), uint256(amount) * recipientCount);
    }
}
