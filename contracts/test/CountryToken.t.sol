// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CountryToken.sol";

/**
 * @title CountryTokenTest
 * @notice Comprehensive test suite for CountryToken
 * @dev Tests role-based access control, minting permissions, and token functionality
 */
contract CountryTokenTest is Test {
    CountryToken public token;
    address public admin;
    address public minter;
    address public alice;
    address public bob;

    /// @notice Role identifiers (must match contract)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Set up test environment before each test
    function setUp() public {
        admin = address(this);
        minter = makeAddr("minter");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy CountryToken
        token = new CountryToken();
    }

    // ============ Deployment Tests ============

    /**
     * @notice Test token metadata matches seed.json configuration
     */
    function testDeployment() public view {
        assertEq(token.name(), "Kenya Shilling Token");
        assertEq(token.symbol(), "KES");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.countryCode(), bytes32("KES"));
    }

    /**
     * @notice Test deployer receives admin role
     */
    function testDeployerHasAdminRole() public view {
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /**
     * @notice Test deployer does not have minter role by default
     * @dev MINTER_ROLE must be explicitly granted to prevent accidental minting
     */
    function testDeployerDoesNotHaveMinterRole() public view {
        assertFalse(token.hasRole(MINTER_ROLE, admin));
    }

    // ============ Role Management Tests ============

    /**
     * @notice Test admin can grant MINTER_ROLE
     */
    function testAdminCanAddMinter() public {
        token.addMinter(minter);
        assertTrue(token.hasRole(MINTER_ROLE, minter));
    }

    /**
     * @notice Test non-admin cannot grant MINTER_ROLE
     */
    function testNonAdminCannotAddMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        token.addMinter(minter);
    }

    /**
     * @notice Test admin can revoke MINTER_ROLE
     */
    function testAdminCanRemoveMinter() public {
        // First grant the role
        token.addMinter(minter);
        assertTrue(token.hasRole(MINTER_ROLE, minter));

        // Then revoke it
        token.removeMinter(minter);
        assertFalse(token.hasRole(MINTER_ROLE, minter));
    }

    /**
     * @notice Test non-admin cannot revoke MINTER_ROLE
     */
    function testNonAdminCannotRemoveMinter() public {
        token.addMinter(minter);

        vm.prank(alice);
        vm.expectRevert();
        token.removeMinter(minter);
    }

    // ============ Minting Tests ============

    /**
     * @notice Test authorized minter can mint tokens
     */
    function testMinterCanMint() public {
        token.addMinter(minter);
        uint256 amount = 1000e18;

        vm.prank(minter);
        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), amount);
    }

    /**
     * @notice Test mint emits TokensMinted event
     */
    function testMintEmitsEvent() public {
        token.addMinter(minter);
        uint256 amount = 1000e18;

        vm.prank(minter);

        // Expect TokensMinted event with indexed parameters
        // expectEmit(checkTopic1, checkTopic2, checkTopic3, checkData)
        vm.expectEmit(true, false, false, true);

        // Emit expected event (to is indexed, amount is data)
        emit TokensMinted(alice, amount, minter);

        // Call the function that should emit the event
        token.mint(alice, amount);
    }

    /// @notice Event declaration for testing (must match contract event)
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);

    /**
     * @notice Test unauthorized address cannot mint
     */
    function testUnauthorizedCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }

    /**
     * @notice Test admin cannot mint without MINTER_ROLE
     * @dev Even admins must explicitly have MINTER_ROLE to mint
     */
    function testAdminCannotMintWithoutMinterRole() public {
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }

    /**
     * @notice Test multiple mints accumulate correctly
     */
    function testMultipleMints() public {
        token.addMinter(minter);

        vm.startPrank(minter);
        token.mint(alice, 500e18);
        token.mint(alice, 300e18);
        token.mint(bob, 200e18);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    /**
     * @notice Test minting to zero address reverts
     * @dev ERC20 standard prevents minting to address(0)
     */
    function testCannotMintToZeroAddress() public {
        token.addMinter(minter);

        vm.prank(minter);
        vm.expectRevert();
        token.mint(address(0), 1000e18);
    }

    // ============ Token Transfer Tests ============

    /**
     * @notice Test tokens can be transferred after minting
     */
    function testTransferAfterMint() public {
        token.addMinter(minter);

        vm.prank(minter);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 300e18);

        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(bob), 300e18);
    }

    // ============ Fuzz Tests ============

    /**
     * @notice Fuzz test minting with random amounts
     * @param to Random recipient address
     * @param amount Random amount to mint
     */
    function testFuzzMint(address to, uint96 amount) public {
        vm.assume(to != address(0)); // Cannot mint to zero address

        token.addMinter(minter);

        vm.prank(minter);
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
    }

    /**
     * @notice Fuzz test role management with random addresses
     * @param randomMinter Random address to grant MINTER_ROLE
     */
    function testFuzzAddMinter(address randomMinter) public {
        vm.assume(randomMinter != address(0));

        token.addMinter(randomMinter);
        assertTrue(token.hasRole(MINTER_ROLE, randomMinter));

        // Verify they can mint
        vm.prank(randomMinter);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    /**
     * @notice Fuzz test unauthorized minting fails for random addresses
     * @param unauthorized Random unauthorized address
     */
    function testFuzzUnauthorizedCannotMint(address unauthorized, uint96 amount) public {
        vm.assume(unauthorized != address(0));
        vm.assume(!token.hasRole(MINTER_ROLE, unauthorized));

        vm.prank(unauthorized);
        vm.expectRevert();
        token.mint(alice, amount);
    }
}
