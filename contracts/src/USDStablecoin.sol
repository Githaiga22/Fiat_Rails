// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title USDStablecoin
 * @notice Mock USD stablecoin for testing FiatRails
 * @dev Simple ERC20 with public mint function for test users
 *
 * Configuration from seed.json:
 * - Symbol: USDT
 * - Name: Tether USD
 * - Decimals: 18
 */
contract USDStablecoin is ERC20, Ownable {
    /**
     * @notice Initialize the stablecoin with name and symbol from seed.json
     */
    constructor() ERC20("Tether USD", "USDT") Ownable(msg.sender) {}

    /**
     * @notice Mint tokens to any address (for testing only)
     * @param to Address to receive minted tokens
     * @param amount Amount to mint (18 decimals)
     * @dev In production, this would be restricted to authorized minters
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Pre-mint tokens for test users (convenience function)
     * @param recipients Array of addresses to receive tokens
     * @param amount Amount each recipient receives
     */
    function preMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }

    /**
     * @notice Decimals is 18 to match production stablecoins
     * @return uint8 Number of decimals (18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
