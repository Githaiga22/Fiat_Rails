// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MintEscrow.sol";
import "../src/UserRegistry.sol";
import "../src/CountryToken.sol";
import "../src/USDStablecoin.sol";

/**
 * @title MintEscrowTest
 * @notice Test suite for MintEscrow contract
 */
contract MintEscrowTest is Test {
    MintEscrow public escrow;
    UserRegistry public registry;
    CountryToken public countryToken;
    USDStablecoin public usd;

    address public admin;
    address public executor;
    address public alice;
    address public bob;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant COUNTRY_CODE = bytes32("KES");
    bytes32 public constant TX_REF_1 = keccak256("TX_001");
    bytes32 public constant TX_REF_2 = keccak256("TX_002");

    event MintIntentSubmitted(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        bytes32 indexed countryCode,
        bytes32 txRef
    );
    event MintExecuted(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        bytes32 indexed countryCode,
        bytes32 txRef
    );
    event MintRefunded(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        string reason
    );

    function setUp() public {
        admin = address(this);
        executor = makeAddr("executor");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        usd = new USDStablecoin();
        countryToken = new CountryToken("Kenya Shilling", "KES");
        registry = new UserRegistry();

        escrow = new MintEscrow(
            address(usd),
            address(countryToken),
            address(registry),
            COUNTRY_CODE
        );

        countryToken.addMinter(address(escrow));
        registry.addComplianceOfficer(admin);
        escrow.grantRole(EXECUTOR_ROLE, executor);

        usd.mint(alice, 10000e18);
        usd.mint(bob, 10000e18);

        vm.prank(alice);
        usd.approve(address(escrow), type(uint256).max);

        vm.prank(bob);
        usd.approve(address(escrow), type(uint256).max);
    }

    function testInitialization() public view {
        assertEq(address(escrow.usdStablecoin()), address(usd));
        assertEq(address(escrow.countryToken()), address(countryToken));
        assertEq(address(escrow.userRegistry()), address(registry));
        assertEq(escrow.countryCode(), COUNTRY_CODE);
        assertTrue(escrow.hasRole(escrow.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(escrow.hasRole(EXECUTOR_ROLE, admin));
    }

    // ============ submitIntent Tests ============

    function testSubmitIntent() public {
        uint256 amount = 100e18;
        uint256 aliceBalanceBefore = usd.balanceOf(alice);
        uint256 escrowBalanceBefore = usd.balanceOf(address(escrow));

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(amount, COUNTRY_CODE, TX_REF_1);

        assertEq(usd.balanceOf(alice), aliceBalanceBefore - amount);
        assertEq(usd.balanceOf(address(escrow)), escrowBalanceBefore + amount);

        IMintEscrow.MintIntent memory intent = escrow.getIntent(intentId);
        assertEq(intent.user, alice);
        assertEq(intent.amount, amount);
        assertEq(intent.countryCode, COUNTRY_CODE);
        assertEq(intent.txRef, TX_REF_1);
        assertEq(uint256(intent.status), uint256(IMintEscrow.MintStatus.Pending));
    }

    function testSubmitIntentEmitsEvent() public {
        uint256 amount = 100e18;

        vm.prank(alice);
        vm.expectEmit(false, true, true, true);
        emit MintIntentSubmitted(bytes32(0), alice, amount, COUNTRY_CODE, TX_REF_1);

        escrow.submitIntent(amount, COUNTRY_CODE, TX_REF_1);
    }

    function testSubmitIntentRevertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IMintEscrow.InvalidAmount.selector);
        escrow.submitIntent(0, COUNTRY_CODE, TX_REF_1);
    }

    function testSubmitIntentRevertsInvalidCountryCode() public {
        vm.prank(alice);
        vm.expectRevert(IMintEscrow.InvalidCountryCode.selector);
        escrow.submitIntent(100e18, bytes32("USD"), TX_REF_1);
    }

    function testSubmitIntentRevertsInsufficientBalance() public {
        address broke = makeAddr("broke");

        vm.prank(broke);
        vm.expectRevert();
        escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);
    }

    function testSubmitIntentMultipleUsers() public {
        vm.prank(alice);
        bytes32 intentId1 = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        vm.prank(bob);
        bytes32 intentId2 = escrow.submitIntent(200e18, COUNTRY_CODE, TX_REF_1);

        assertFalse(intentId1 == intentId2);

        IMintEscrow.MintIntent memory intent1 = escrow.getIntent(intentId1);
        IMintEscrow.MintIntent memory intent2 = escrow.getIntent(intentId2);

        assertEq(intent1.user, alice);
        assertEq(intent2.user, bob);
        assertEq(intent1.amount, 100e18);
        assertEq(intent2.amount, 200e18);
    }

    // ============ executeMint Tests ============

    function testExecuteMint() public {
        registry.updateUser(alice, 50, keccak256("KYC"), true);

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        uint256 aliceTokenBalanceBefore = countryToken.balanceOf(alice);

        vm.prank(executor);
        escrow.executeMint(intentId);

        assertEq(countryToken.balanceOf(alice), aliceTokenBalanceBefore + 100e18);
        assertEq(uint256(escrow.getIntentStatus(intentId)), uint256(IMintEscrow.MintStatus.Executed));
    }

    function testExecuteMintEmitsEvent() public {
        registry.updateUser(alice, 50, keccak256("KYC"), true);

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit MintExecuted(intentId, alice, 100e18, COUNTRY_CODE, TX_REF_1);

        escrow.executeMint(intentId);
    }

    function testExecuteMintRequiresExecutorRole() public {
        registry.updateUser(alice, 50, keccak256("KYC"), true);

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        vm.prank(alice);
        vm.expectRevert();
        escrow.executeMint(intentId);
    }

    function testExecuteMintRevertsNonCompliantUser() public {
        registry.updateUser(alice, 90, keccak256("KYC"), true);

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        vm.prank(executor);
        vm.expectRevert(IMintEscrow.UserNotCompliant.selector);
        escrow.executeMint(intentId);
    }

    function testExecuteMintRevertsIntentNotFound() public {
        vm.prank(executor);
        vm.expectRevert(IMintEscrow.IntentNotFound.selector);
        escrow.executeMint(bytes32("nonexistent"));
    }

    function testExecuteMintRevertsAlreadyExecuted() public {
        registry.updateUser(alice, 50, keccak256("KYC"), true);

        vm.prank(alice);
        bytes32 intentId = escrow.submitIntent(100e18, COUNTRY_CODE, TX_REF_1);

        vm.prank(executor);
        escrow.executeMint(intentId);

        vm.prank(executor);
        vm.expectRevert(IMintEscrow.IntentAlreadyExecuted.selector);
        escrow.executeMint(intentId);
    }
}
