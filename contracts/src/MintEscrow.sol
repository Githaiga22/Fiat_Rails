// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../IMintEscrow.sol";
import "./UserRegistry.sol";
import "./CountryToken.sol";

/**
 * @title MintEscrow
 * @notice Escrow for fiat-to-crypto minting with compliance checks
 * @dev Accepts USD deposits, mints country tokens for compliant users
 */
contract MintEscrow is IMintEscrow, AccessControl, ReentrancyGuard {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    IERC20 public usdStablecoin;
    CountryToken public countryToken;
    UserRegistry public userRegistry;
    bytes32 public immutable countryCode;

    mapping(bytes32 => MintIntent) private intents;

    constructor(
        address _usdStablecoin,
        address _countryToken,
        address _userRegistry,
        bytes32 _countryCode
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);

        usdStablecoin = IERC20(_usdStablecoin);
        countryToken = CountryToken(_countryToken);
        userRegistry = UserRegistry(_userRegistry);
        countryCode = _countryCode;
    }

    /**
     * @notice Submit mint intent and deposit USD
     * @param amount Amount of USD to deposit
     * @param _countryCode Target country code
     * @param txRef Off-chain transaction reference
     * @return intentId Unique intent identifier
     */
    function submitIntent(
        uint256 amount,
        bytes32 _countryCode,
        bytes32 txRef
    ) external nonReentrant returns (bytes32 intentId) {
        if (amount == 0) revert InvalidAmount();
        if (_countryCode != countryCode) revert InvalidCountryCode();

        intentId = keccak256(abi.encodePacked(msg.sender, txRef, block.timestamp));

        if (intents[intentId].timestamp != 0) revert IntentAlreadyExists();

        intents[intentId] = MintIntent({
            user: msg.sender,
            amount: amount,
            countryCode: _countryCode,
            txRef: txRef,
            timestamp: block.timestamp,
            status: MintStatus.Pending
        });

        if (!usdStablecoin.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        emit MintIntentSubmitted(intentId, msg.sender, amount, _countryCode, txRef);
    }

    /**
     * @notice Execute mint for compliant user
     * @param intentId Intent to execute
     */
    function executeMint(bytes32 intentId) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        MintIntent storage intent = intents[intentId];

        if (intent.timestamp == 0) revert IntentNotFound();
        if (intent.status != MintStatus.Pending) revert IntentAlreadyExecuted();

        if (!userRegistry.isCompliant(intent.user)) {
            revert UserNotCompliant();
        }

        intent.status = MintStatus.Executed;

        countryToken.mint(intent.user, intent.amount);

        emit MintExecuted(intentId, intent.user, intent.amount, intent.countryCode, intent.txRef);
    }

    /**
     * @notice Refund intent
     * @param intentId Intent to refund
     * @param reason Refund reason
     */
    function refundIntent(bytes32 intentId, string calldata reason) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        MintIntent storage intent = intents[intentId];

        if (intent.timestamp == 0) revert IntentNotFound();
        if (intent.status != MintStatus.Pending) revert IntentAlreadyExecuted();

        intent.status = MintStatus.Refunded;

        if (!usdStablecoin.transfer(intent.user, intent.amount)) {
            revert TransferFailed();
        }

        emit MintRefunded(intentId, intent.user, intent.amount, reason);
    }
}
