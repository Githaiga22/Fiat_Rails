// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMintEscrow
 * @notice Escrow for mint intents with compliance checks
 * @dev Accepts USD stablecoin deposits, mints country tokens after compliance verification
 * 
 * Requirements:
 * - Accept deposit intents (USD stablecoin)
 * - Check UserRegistry for compliance before minting
 * - Execute mint only if compliant
 * - Emit structured events for off-chain indexing
 * - Handle refunds if compliance check fails
 * - Prevent double-execution of same intent
 */
interface IMintEscrow {
    // ============ Structs ============
    
    struct MintIntent {
        address user;              // User submitting intent
        uint256 amount;            // Amount in USD stablecoin (18 decimals)
        bytes32 countryCode;       // ISO country code (e.g., "KES" for Kenya)
        bytes32 txRef;             // Off-chain transaction reference
        uint256 timestamp;         // Submission timestamp
        MintStatus status;         // Current status
    }

    enum MintStatus {
        Pending,
        Executed,
        Refunded,
        Failed
    }

    // ============ Events ============
    
    /**
     * @notice Emitted when a mint intent is submitted
     * @param intentId Unique identifier for this intent
     * @param user User submitting the intent
     * @param amount Amount to mint
     * @param countryCode Target country token
     * @param txRef Off-chain transaction reference (e.g., M-PESA ID)
     */
    event MintIntentSubmitted(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        bytes32 indexed countryCode,
        bytes32 txRef
    );

    /**
     * @notice Emitted when a mint is executed
     * @param intentId Intent that was executed
     * @param user User receiving the tokens
     * @param amount Amount minted
     * @param countryCode Country token minted
     * @param txRef Transaction reference
     */
    event MintExecuted(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        bytes32 indexed countryCode,
        bytes32 txRef
    );

    /**
     * @notice Emitted when an intent is refunded
     * @param intentId Intent that was refunded
     * @param user User receiving refund
     * @param amount Amount refunded
     * @param reason Reason for refund
     */
    event MintRefunded(
        bytes32 indexed intentId,
        address indexed user,
        uint256 amount,
        string reason
    );

    // ============ Errors ============
    
    error IntentAlreadyExists();
    error IntentNotFound();
    error UserNotCompliant();
    error InvalidAmount();
    error InvalidCountryCode();
    error IntentAlreadyExecuted();
    error TransferFailed();

    // ============ Core Functions ============

    /**
     * @notice Submit a mint intent
     * @param amount Amount of USD stablecoin to deposit
     * @param countryCode ISO country code for target token
     * @param txRef Off-chain transaction reference
     * @return intentId Unique identifier for this intent
     */
    function submitIntent(
        uint256 amount,
        bytes32 countryCode,
        bytes32 txRef
    ) external returns (bytes32 intentId);

    /**
     * @notice Execute a mint intent (called by authorized callback service)
     * @param intentId Intent to execute
     * @dev Must check compliance before minting
     */
    function executeMint(bytes32 intentId) external;

    /**
     * @notice Refund a failed or non-compliant intent
     * @param intentId Intent to refund
     * @param reason Reason for refund
     */
    function refundIntent(bytes32 intentId, string calldata reason) external;

    /**
     * @notice Get intent details
     * @param intentId Intent identifier
     * @return MintIntent struct
     */
    function getIntent(bytes32 intentId) external view returns (MintIntent memory);

    /**
     * @notice Check if an intent exists and its status
     * @param intentId Intent identifier
     * @return status Current status
     */
    function getIntentStatus(bytes32 intentId) external view returns (MintStatus);

    /**
     * @notice Set the UserRegistry address
     * @param registry Address of UserRegistry contract
     */
    function setUserRegistry(address registry) external;

    /**
     * @notice Set the USD stablecoin address
     * @param token Address of USD stablecoin
     */
    function setStablecoin(address token) external;
}

