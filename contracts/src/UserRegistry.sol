// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../IUserRegistry.sol";

/**
 * @title UserRegistry
 * @notice Stores user compliance data including risk scores and attestation hashes
 * @dev Implements IUserRegistry interface with role-based access control
 *
 * Compliance Configuration from seed.json:
 * - Max Risk Score: 83 (0-83 acceptable, >83 non-compliant)
 * - Require Attestation: true
 * - Min Attestation Age: 0 seconds
 *
 * Security:
 * - Only COMPLIANCE_OFFICER_ROLE can update user data
 * - Public read access for compliance checks
 * - Events emitted for all updates (audit trail)
 *
 * @custom:security-contact security@fiatrails.io
 */
contract UserRegistry is IUserRegistry, AccessControl {
    /// @notice Role identifier for compliance officers who can update user data
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    /// @notice Maximum acceptable risk score from seed.json
    uint8 public constant MAX_RISK_SCORE = 83;

    /// @notice Mapping from user address to their compliance data
    mapping(address => UserCompliance) private users;

    /**
     * @notice Initialize the registry with admin role
     * @dev Grants DEFAULT_ADMIN_ROLE to deployer
     *      Admin must explicitly grant COMPLIANCE_OFFICER_ROLE to authorized addresses
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Register or update a user's compliance data
     * @param user Address of the user
     * @param riskScore Risk score (0-100 scale, 0 = lowest risk)
     * @param attestationHash Hash of compliance documentation or ZK proof
     * @param isVerified Whether user has completed KYC verification
     *
     * @dev Requirements:
     * - Only callable by COMPLIANCE_OFFICER_ROLE
     * - Risk score must be ≤ 100
     * - Emits UserComplianceUpdated event
     *
     * Security considerations:
     * - Attestation hash should be hash of signed document or ZK proof
     * - Risk score calculated off-chain based on compliance checks
     * - lastUpdated timestamp prevents stale compliance data
     */
    function updateUser(
        address user,
        uint8 riskScore,
        bytes32 attestationHash,
        bool isVerified
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        // Validate risk score is within acceptable range (0-100)
        if (riskScore > 100) {
            revert InvalidRiskScore();
        }

        // Update user compliance data
        users[user] = UserCompliance({
            riskScore: riskScore,
            attestationHash: attestationHash,
            lastUpdated: block.timestamp,
            isVerified: isVerified
        });

        // Emit event for off-chain indexing and audit trail
        emit UserComplianceUpdated(user, riskScore, attestationHash, isVerified);
    }

    /**
     * @notice Get user compliance data
     * @param user Address to query
     * @return UserCompliance struct with all compliance data
     *
     * @dev Returns default struct (all zeros) if user not registered
     *      Check isVerified or lastUpdated to determine if user exists
     */
    function getUser(address user) external view returns (UserCompliance memory) {
        return users[user];
    }

    /**
     * @notice Check if user is compliant for minting operations
     * @param user Address to check
     * @return bool True if user meets all compliance requirements
     *
     * @dev Compliance requirements (from seed.json):
     * 1. User must be verified (isVerified == true)
     * 2. Risk score must be ≤ MAX_RISK_SCORE (83)
     * 3. Must have attestation hash (non-zero) since requireAttestation == true
     *
     * Note: This is the critical function used by MintEscrow before executing mints
     */
    function isCompliant(address user) external view returns (bool) {
        UserCompliance memory compliance = users[user];

        // Check all compliance requirements
        return compliance.isVerified && // Must be KYC verified
            compliance.riskScore <= MAX_RISK_SCORE && // Risk within acceptable range
            compliance.attestationHash != bytes32(0); // Must have attestation
    }

    /**
     * @notice Get user's current risk score
     * @param user Address to query
     * @return uint8 Risk score (0-100)
     *
     * @dev Returns 0 if user not registered
     *      Use getUser() to check if user exists (lastUpdated > 0)
     */
    function getRiskScore(address user) external view returns (uint8) {
        return users[user].riskScore;
    }

    /**
     * @notice Get user's attestation hash
     * @param user Address to query
     * @return bytes32 Attestation hash (hash of compliance documents or ZK proof)
     *
     * @dev Returns bytes32(0) if user not registered or no attestation provided
     *      Attestation hash is used to link on-chain compliance to off-chain documents
     */
    function getAttestationHash(address user) external view returns (bytes32) {
        return users[user].attestationHash;
    }

    /**
     * @notice Grant COMPLIANCE_OFFICER_ROLE to an address
     * @param officer Address to grant compliance officer permissions
     * @dev Only callable by admin
     *      Compliance officers can update user risk scores and attestations
     */
    function addComplianceOfficer(address officer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(COMPLIANCE_OFFICER_ROLE, officer);
    }

    /**
     * @notice Revoke COMPLIANCE_OFFICER_ROLE from an address
     * @param officer Address to revoke compliance officer permissions from
     * @dev Only callable by admin
     *      Used for role rotation or security incidents
     */
    function removeComplianceOfficer(address officer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(COMPLIANCE_OFFICER_ROLE, officer);
    }

    /**
     * @notice Check if user has been registered
     * @param user Address to check
     * @return bool True if user has been registered (lastUpdated > 0)
     *
     * @dev Helper function to distinguish between non-existent and zero-risk users
     */
    function isRegistered(address user) external view returns (bool) {
        return users[user].lastUpdated > 0;
    }
}
