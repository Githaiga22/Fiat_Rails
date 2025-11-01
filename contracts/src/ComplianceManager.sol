// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../IComplianceManager.sol";
import "./UserRegistry.sol";

/**
 * @title ComplianceManager
 * @notice UUPS upgradeable compliance orchestrator
 * @dev Roles: COMPLIANCE_OFFICER (updates), UPGRADER_ROLE (upgrades), DEFAULT_ADMIN_ROLE
 */
contract ComplianceManager is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IComplianceManager
{
    /// @notice Role for compliance officers who manage user risk and attestations
    bytes32 public constant COMPLIANCE_OFFICER = keccak256("COMPLIANCE_OFFICER");

    /// @notice Role for addresses authorized to upgrade the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    UserRegistry public userRegistry;
    uint8 public constant MAX_RISK_SCORE = 83;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize contract with admin and registry
     * @param admin Address for all roles
     * @param _userRegistry UserRegistry contract address
     */
    function initialize(address admin, address _userRegistry) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_OFFICER, admin);
        _grantRole(UPGRADER_ROLE, admin);

        userRegistry = UserRegistry(_userRegistry);
    }

    /**
     * @notice Update user's risk score
     * @param user Address of user
     * @param riskScore New risk score (0-100)
     */
    function updateUserRisk(address user, uint8 riskScore) external whenNotPaused onlyRole(COMPLIANCE_OFFICER) {
        if (riskScore > 100) {
            revert InvalidRiskScore();
        }

        IUserRegistry.UserCompliance memory current = userRegistry.getUser(user);
        userRegistry.updateUser(user, riskScore, current.attestationHash, current.isVerified);

        emit UserRiskUpdated(user, riskScore, msg.sender, block.timestamp);
    }

    /**
     * @notice Record attestation for user
     * @param user Address of user
     * @param attestationHash Hash of attestation document
     * @param attestationType Type identifier
     */
    function recordAttestation(
        address user,
        bytes32 attestationHash,
        bytes32 attestationType
    ) external whenNotPaused onlyRole(COMPLIANCE_OFFICER) {
        if (attestationHash == bytes32(0)) {
            revert InvalidAttestation();
        }

        IUserRegistry.UserCompliance memory current = userRegistry.getUser(user);
        userRegistry.updateUser(user, current.riskScore, attestationHash, current.isVerified);

        emit AttestationRecorded(user, attestationHash, attestationType, msg.sender);
    }

    /**
     * @notice Check if user is compliant
     * @param user Address to check
     * @return bool True if compliant
     */
    function isCompliant(address user) external view returns (bool) {
        return userRegistry.isCompliant(user);
    }

    /**
     * @notice Pause compliance operations (admin only)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause compliance operations (admin only)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Authorize upgrade (UPGRADER_ROLE only)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
