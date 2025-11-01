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
}
