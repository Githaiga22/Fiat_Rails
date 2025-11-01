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
}
