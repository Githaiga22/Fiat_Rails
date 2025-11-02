// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../IUserRegistry.sol";

/**
 * @title UserRegistry
 * @notice Stores user compliance data with risk scores and attestations
 * @dev COMPLIANCE_OFFICER_ROLE required for writes. Max risk score: 83 (from seed.json)
 */
contract UserRegistry is IUserRegistry, AccessControl {
    /// @notice Role identifier for compliance officers who can update user data
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    /// @notice Maximum acceptable risk score from seed.json
    uint8 public constant MAX_RISK_SCORE = 83;

    /// @notice Mapping from user address to their compliance data
    mapping(address => UserCompliance) private users;

    /// @notice Grants deployer DEFAULT_ADMIN_ROLE
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Update user compliance data (requires COMPLIANCE_OFFICER_ROLE)
     * @param user Address of the user
     * @param riskScore Risk score (0-100)
     * @param attestationHash Hash of compliance documentation
     * @param isVerified KYC verification status
     */
    function updateUser(address user, uint8 riskScore, bytes32 attestationHash, bool isVerified)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
    {
        if (riskScore > 100) {
            revert InvalidRiskScore();
        }

        users[user] = UserCompliance({
            riskScore: riskScore,
            attestationHash: attestationHash,
            lastUpdated: block.timestamp,
            isVerified: isVerified
        });

        emit UserComplianceUpdated(user, riskScore, attestationHash, isVerified);
    }

    /**
     * @notice Get user compliance data
     * @param user Address to query
     * @return UserCompliance struct (returns default struct if user not registered)
     */
    function getUser(address user) external view returns (UserCompliance memory) {
        return users[user];
    }

    /**
     * @notice Check if user meets compliance requirements
     * @param user Address to check
     * @return bool True if verified, risk score ≤ 83, and has attestation
     */
    function isCompliant(address user) external view returns (bool) {
        UserCompliance memory compliance = users[user];
        return
            compliance.isVerified && compliance.riskScore <= MAX_RISK_SCORE && compliance.attestationHash != bytes32(0);
    }

    /**
     * @notice Get user's risk score
     * @param user Address to query
     * @return uint8 Risk score (0 if not registered)
     */
    function getRiskScore(address user) external view returns (uint8) {
        return users[user].riskScore;
    }

    /**
     * @notice Get user's attestation hash
     * @param user Address to query
     * @return bytes32 Attestation hash
     */
    function getAttestationHash(address user) external view returns (bytes32) {
        return users[user].attestationHash;
    }

    /**
     * @notice Grant COMPLIANCE_OFFICER_ROLE (admin only)
     * @param officer Address to grant role
     */
    function addComplianceOfficer(address officer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(COMPLIANCE_OFFICER_ROLE, officer);
    }

    /**
     * @notice Revoke COMPLIANCE_OFFICER_ROLE (admin only)
     * @param officer Address to revoke role
     */
    function removeComplianceOfficer(address officer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(COMPLIANCE_OFFICER_ROLE, officer);
    }

    /**
     * @notice Check if user is registered
     * @param user Address to check
     * @return bool True if lastUpdated > 0
     */
    function isRegistered(address user) external view returns (bool) {
        return users[user].lastUpdated > 0;
    }
}
