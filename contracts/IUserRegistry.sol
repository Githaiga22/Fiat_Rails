// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IUserRegistry
 * @notice User compliance data storage
 * @dev Stores risk scores and attestation hashes per user
 * 
 * Requirements:
 * - Store risk score (0-100) per user
 * - Store attestation hash (off-chain doc/ZK proof reference)
 * - Query interface for compliance checks
 * - Consider access control (who can write?)
 */
interface IUserRegistry {
    // ============ Structs ============
    
    struct UserCompliance {
        uint8 riskScore;           // 0-100 scale (0 = lowest risk)
        bytes32 attestationHash;   // Hash of off-chain compliance doc
        uint256 lastUpdated;       // Timestamp of last update
        bool isVerified;           // Has passed initial KYC
    }

    // ============ Events ============
    
    /**
     * @notice Emitted when user compliance data is updated
     * @param user Address of the user
     * @param riskScore New risk score
     * @param attestationHash New attestation hash
     * @param isVerified Verification status
     */
    event UserComplianceUpdated(
        address indexed user,
        uint8 riskScore,
        bytes32 attestationHash,
        bool isVerified
    );

    // ============ Errors ============
    
    error UserNotFound();
    error InvalidRiskScore();
    error Unauthorized();

    // ============ Core Functions ============

    /**
     * @notice Register or update a user's compliance data
     * @param user Address of the user
     * @param riskScore Risk score (0-100)
     * @param attestationHash Hash of compliance documentation
     * @param isVerified Whether user has completed KYC
     */
    function updateUser(
        address user,
        uint8 riskScore,
        bytes32 attestationHash,
        bool isVerified
    ) external;

    /**
     * @notice Get user compliance data
     * @param user Address to query
     * @return UserCompliance struct with all data
     */
    function getUser(address user) external view returns (UserCompliance memory);

    /**
     * @notice Check if user is compliant (verified + acceptable risk)
     * @param user Address to check
     * @return bool True if compliant
     */
    function isCompliant(address user) external view returns (bool);

    /**
     * @notice Get user's current risk score
     * @param user Address to query
     * @return uint8 Risk score
     */
    function getRiskScore(address user) external view returns (uint8);

    /**
     * @notice Get user's attestation hash
     * @param user Address to query
     * @return bytes32 Attestation hash
     */
    function getAttestationHash(address user) external view returns (bytes32);
}

