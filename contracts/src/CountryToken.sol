// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CountryToken
 * @notice ERC20 for Kenya Shilling (KES) with role-based minting
 * @dev MINTER_ROLE required for minting. 18 decimals for 1:1 USD conversion
 */
contract CountryToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public immutable countryCode;

    event TokensMinted(address indexed to, uint256 amount, address indexed minter);

    /// @notice Grants deployer DEFAULT_ADMIN_ROLE, sets countryCode to "KES"
    constructor() ERC20("Kenya Shilling Token", "KES") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        countryCode = bytes32("KES");
    }

    /**
     * @notice Mint tokens (requires MINTER_ROLE)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit TokensMinted(to, amount, msg.sender);
    }

    /**
     * @notice Grant MINTER_ROLE (admin only)
     * @param minter Address to grant role
     */
    function addMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Revoke MINTER_ROLE (admin only)
     * @param minter Address to revoke role
     */
    function removeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MINTER_ROLE, minter);
    }

    /// @notice Returns 18 decimals for 1:1 USD conversion
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
