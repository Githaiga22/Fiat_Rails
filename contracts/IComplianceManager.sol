// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IComplianceManager
 * @notice Core compliance orchestrator for FiatRails
 * @dev Must be upgradeable, pausable, and role-gated
 * 
 * Requirements:
 * - Implement UUPS upgradeability pattern (or justify alternative in ADR)
 * - Role-based access control (ADMIN, COMPLIANCE_OFFICER, UPGRADER)
 * - Pausable mechanism for emergency stops
 * - Events must be indexed appropriately for off-chain indexing
 */
interface IComplianceManager {
    // ============ Events ============
    
    /**
     * @notice Emitted when a user's risk score is updated
     * @param user Address of the user
     * @param newRiskScore New risk score (0-100 scale)
     * @param updatedBy Address that performed the update
     * @param timestamp Block timestamp
     */
    event UserRiskUpdated(
        address indexed user,
        uint8 newRiskScore,
        address indexed updatedBy,
        uint256 timestamp
    );

    /**
     * @notice Emitted when an attestation is recorded
     * @param user Address of the user
     * @param attestationHash Hash of off-chain document or ZK proof
     * @param attestationType Type of attestation (KYC, AML, etc)
     * @param recordedBy Address that recorded the attestation
     */
    event AttestationRecorded(
        address indexed user,
        bytes32 indexed attestationHash,
        bytes32 attestationType,
        address indexed recordedBy
    );

    // ============ Errors ============
    
    error Unauthorized();
    error SystemPaused();
    error InvalidRiskScore();
    error InvalidAttestation();

    // ============ Core Functions ============

    /**
     * @notice Update a user's risk score
     * @param user Address of the user
     * @param riskScore New risk score (0-100)
     */
    function updateUserRisk(address user, uint8 riskScore) external;

    /**
     * @notice Record an attestation for a user
     * @param user Address of the user
     * @param attestationHash Hash of the attestation document
     * @param attestationType Type identifier
     */
    function recordAttestation(
        address user,
        bytes32 attestationHash,
        bytes32 attestationType
    ) external;

    /**
     * @notice Check if a user is compliant for operations
     * @param user Address to check
     * @return bool True if user meets compliance requirements
     */
    function isCompliant(address user) external view returns (bool);

    /**
     * @notice Pause all compliance operations
     * @dev Only callable by ADMIN role
     */
    function pause() external;

    /**
     * @notice Resume compliance operations
     * @dev Only callable by ADMIN role
     */
    function unpause() external;
}

