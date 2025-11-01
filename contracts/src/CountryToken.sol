// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CountryToken
 * @notice ERC20 token representing country-specific stablecoin
 * @dev Implements role-based minting for MintEscrow contract
 *
 * Configuration from seed.json:
 * - Symbol: KES (Kenya Shilling)
 * - Name: Kenya Shilling Token
 * - Country Code: KES
 * - Decimals: 18 (matches USD stablecoin for 1:1 conversion)
 *
 * Security:
 * - Only addresses with MINTER_ROLE can mint new tokens
 * - DEFAULT_ADMIN_ROLE can grant/revoke roles
 * - Minting restricted to prevent unauthorized token creation
 */
contract CountryToken is ERC20, AccessControl {
    /// @notice Role identifier for addresses allowed to mint tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Country code identifier (e.g., "KES" for Kenya)
    bytes32 public immutable countryCode;

    /**
     * @notice Emitted when tokens are minted to a user
     * @param to Address receiving the minted tokens
     * @param amount Amount of tokens minted (18 decimals)
     * @param minter Address that executed the mint (has MINTER_ROLE)
     */
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);

    /**
     * @notice Initialize the country token with name and symbol from seed.json
     * @dev Grants DEFAULT_ADMIN_ROLE to deployer
     *      Deployer must explicitly grant MINTER_ROLE to MintEscrow contract
     */
    constructor() ERC20("Kenya Shilling Token", "KES") {
        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Store country code (matches symbol for this implementation)
        countryCode = bytes32("KES");
    }

    /**
     * @notice Mint new tokens to a specified address
     * @param to Address to receive the minted tokens
     * @param amount Amount to mint (18 decimals)
     * @dev Only callable by addresses with MINTER_ROLE
     *      Emits TokensMinted event for off-chain tracking
     *
     * Security considerations:
     * - Prevents unauthorized minting
     * - Used by MintEscrow after compliance checks pass
     * - 1:1 ratio with USD stablecoin (both 18 decimals)
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit TokensMinted(to, amount, msg.sender);
    }

    /**
     * @notice Grant MINTER_ROLE to an address (typically MintEscrow contract)
     * @param minter Address to grant minting permissions
     * @dev Only callable by admin
     *      Required during deployment to authorize MintEscrow
     */
    function addMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Revoke MINTER_ROLE from an address
     * @param minter Address to revoke minting permissions from
     * @dev Only callable by admin
     *      Used to rotate authorized minters or respond to security incidents
     */
    function removeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Returns the number of decimals (18 to match USD stablecoin)
     * @return uint8 Number of decimals
     * @dev 18 decimals enables 1:1 conversion with USD stablecoin
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
