// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UserRegistry.sol";

/**
 * @title UserRegistryTest
 * @notice Comprehensive test suite for UserRegistry contract
 * @dev Tests compliance checks, role management, and risk scoring
 */
contract UserRegistryTest is Test {
    UserRegistry public registry;
    address public admin;
    address public complianceOfficer;
    address public alice;
    address public bob;

    /// @notice Role identifiers (must match contract)
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Constants from seed.json
    uint8 public constant MAX_RISK_SCORE = 83;

    /// @notice Test data
    bytes32 public constant TEST_ATTESTATION = keccak256("KYC_DOCUMENT_HASH");

    /// @notice Event declarations for testing
    event UserComplianceUpdated(address indexed user, uint8 riskScore, bytes32 attestationHash, bool isVerified);

    /**
     * @notice Set up test environment before each test
     */
    function setUp() public {
        admin = address(this);
        complianceOfficer = makeAddr("complianceOfficer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy UserRegistry
        registry = new UserRegistry();

        // Grant compliance officer role for most tests
        registry.addComplianceOfficer(complianceOfficer);
    }

    // ============ Deployment Tests ============

    /**
     * @notice Test deployer receives admin role
     */
    function testDeployerHasAdminRole() public view {
        assertTrue(registry.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /**
     * @notice Test max risk score constant matches seed.json
     */
    function testMaxRiskScoreConstant() public view {
        assertEq(registry.MAX_RISK_SCORE(), 83);
    }

    // ============ Role Management Tests ============

    /**
     * @notice Test admin can grant COMPLIANCE_OFFICER_ROLE
     */
    function testAdminCanAddComplianceOfficer() public {
        address newOfficer = makeAddr("newOfficer");
        registry.addComplianceOfficer(newOfficer);
        assertTrue(registry.hasRole(COMPLIANCE_OFFICER_ROLE, newOfficer));
    }

    /**
     * @notice Test non-admin cannot grant COMPLIANCE_OFFICER_ROLE
     */
    function testNonAdminCannotAddComplianceOfficer() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.addComplianceOfficer(alice);
    }

    /**
     * @notice Test admin can revoke COMPLIANCE_OFFICER_ROLE
     */
    function testAdminCanRemoveComplianceOfficer() public {
        assertTrue(registry.hasRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer));

        registry.removeComplianceOfficer(complianceOfficer);

        assertFalse(registry.hasRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer));
    }

    // ============ Update User Tests ============

    /**
     * @notice Test compliance officer can update user data
     */
    function testComplianceOfficerCanUpdateUser() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);

        IUserRegistry.UserCompliance memory compliance = registry.getUser(alice);
        assertEq(compliance.riskScore, 50);
        assertEq(compliance.attestationHash, TEST_ATTESTATION);
        assertTrue(compliance.isVerified);
        assertGt(compliance.lastUpdated, 0);
    }

    /**
     * @notice Test updateUser emits UserComplianceUpdated event
     */
    function testUpdateUserEmitsEvent() public {
        vm.prank(complianceOfficer);

        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit UserComplianceUpdated(alice, 50, TEST_ATTESTATION, true);

        registry.updateUser(alice, 50, TEST_ATTESTATION, true);
    }

    /**
     * @notice Test unauthorized address cannot update user
     */
    function testUnauthorizedCannotUpdateUser() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);
    }

    /**
     * @notice Test cannot set risk score above 100
     */
    function testCannotSetRiskScoreAbove100() public {
        vm.prank(complianceOfficer);
        vm.expectRevert(IUserRegistry.InvalidRiskScore.selector);
        registry.updateUser(alice, 101, TEST_ATTESTATION, true);
    }

    /**
     * @notice Test can update user multiple times (latest wins)
     */
    function testCanUpdateUserMultipleTimes() public {
        vm.startPrank(complianceOfficer);

        // First update
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);
        assertEq(registry.getRiskScore(alice), 50);

        // Second update (lower risk)
        bytes32 newAttestation = keccak256("NEW_KYC");
        registry.updateUser(alice, 30, newAttestation, true);

        vm.stopPrank();

        // Verify latest update
        IUserRegistry.UserCompliance memory compliance = registry.getUser(alice);
        assertEq(compliance.riskScore, 30);
        assertEq(compliance.attestationHash, newAttestation);
    }

    // ============ Compliance Check Tests ============

    /**
     * @notice Test compliant user (verified, low risk, has attestation)
     */
    function testCompliantUser() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);

        assertTrue(registry.isCompliant(alice));
    }

    /**
     * @notice Test user with risk score at max threshold (83) is compliant
     */
    function testUserAtMaxRiskScoreIsCompliant() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, MAX_RISK_SCORE, TEST_ATTESTATION, true);

        assertTrue(registry.isCompliant(alice));
    }

    /**
     * @notice Test user with risk score above max (84) is non-compliant
     */
    function testUserAboveMaxRiskScoreIsNonCompliant() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, MAX_RISK_SCORE + 1, TEST_ATTESTATION, true);

        assertFalse(registry.isCompliant(alice));
    }

    /**
     * @notice Test unverified user is non-compliant
     */
    function testUnverifiedUserIsNonCompliant() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, TEST_ATTESTATION, false); // isVerified = false

        assertFalse(registry.isCompliant(alice));
    }

    /**
     * @notice Test user without attestation is non-compliant
     */
    function testUserWithoutAttestationIsNonCompliant() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, bytes32(0), true); // No attestation

        assertFalse(registry.isCompliant(alice));
    }

    /**
     * @notice Test unregistered user is non-compliant
     */
    function testUnregisteredUserIsNonCompliant() public {
        assertFalse(registry.isCompliant(alice));
    }

    // ============ Getter Function Tests ============

    /**
     * @notice Test getRiskScore returns correct value
     */
    function testGetRiskScore() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 75, TEST_ATTESTATION, true);

        assertEq(registry.getRiskScore(alice), 75);
    }

    /**
     * @notice Test getRiskScore returns 0 for unregistered user
     */
    function testGetRiskScoreForUnregistered() public view {
        assertEq(registry.getRiskScore(alice), 0);
    }

    /**
     * @notice Test getAttestationHash returns correct value
     */
    function testGetAttestationHash() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);

        assertEq(registry.getAttestationHash(alice), TEST_ATTESTATION);
    }

    /**
     * @notice Test isRegistered returns true for registered users
     */
    function testIsRegistered() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, TEST_ATTESTATION, true);

        assertTrue(registry.isRegistered(alice));
    }

    /**
     * @notice Test isRegistered returns false for unregistered users
     */
    function testIsNotRegistered() public view {
        assertFalse(registry.isRegistered(alice));
    }

    // ============ Edge Case Tests ============

    /**
     * @notice Test registering user with zero risk score
     */
    function testZeroRiskScoreUser() public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 0, TEST_ATTESTATION, true);

        assertTrue(registry.isCompliant(alice));
        assertEq(registry.getRiskScore(alice), 0);
    }

    /**
     * @notice Test getUser for unregistered user returns default struct
     */
    function testGetUserForUnregistered() public view {
        IUserRegistry.UserCompliance memory compliance = registry.getUser(alice);

        assertEq(compliance.riskScore, 0);
        assertEq(compliance.attestationHash, bytes32(0));
        assertEq(compliance.lastUpdated, 0);
        assertFalse(compliance.isVerified);
    }

    // ============ Fuzz Tests ============

    /**
     * @notice Fuzz test risk score boundaries (0-83 compliant, 84-100 non-compliant)
     * @param riskScore Random risk score to test
     */
    function testFuzzRiskScoreBoundaries(uint8 riskScore) public {
        vm.assume(riskScore <= 100); // Only test valid risk scores

        vm.prank(complianceOfficer);
        registry.updateUser(alice, riskScore, TEST_ATTESTATION, true);

        bool shouldBeCompliant = riskScore <= MAX_RISK_SCORE;
        assertEq(registry.isCompliant(alice), shouldBeCompliant);
    }

    /**
     * @notice Fuzz test updating multiple users with random data
     * @param user Random user address
     * @param riskScore Random risk score
     */
    function testFuzzMultipleUsers(address user, uint8 riskScore) public {
        vm.assume(user != address(0));
        vm.assume(riskScore <= 100);

        vm.prank(complianceOfficer);
        registry.updateUser(user, riskScore, TEST_ATTESTATION, true);

        assertEq(registry.getRiskScore(user), riskScore);
        assertTrue(registry.isRegistered(user));
    }

    /**
     * @notice Fuzz test attestation hash variations
     * @param attestation Random attestation hash
     */
    function testFuzzAttestationHash(bytes32 attestation) public {
        vm.prank(complianceOfficer);
        registry.updateUser(alice, 50, attestation, true);

        // User is only compliant if attestation is non-zero
        bool shouldBeCompliant = attestation != bytes32(0);
        assertEq(registry.isCompliant(alice), shouldBeCompliant);
        assertEq(registry.getAttestationHash(alice), attestation);
    }

    /**
     * @notice Fuzz test invalid risk scores (> 100) always revert
     * @param invalidScore Random score above 100
     */
    function testFuzzInvalidRiskScores(uint8 invalidScore) public {
        vm.assume(invalidScore > 100);

        vm.prank(complianceOfficer);
        vm.expectRevert(IUserRegistry.InvalidRiskScore.selector);
        registry.updateUser(alice, invalidScore, TEST_ATTESTATION, true);
    }
}
