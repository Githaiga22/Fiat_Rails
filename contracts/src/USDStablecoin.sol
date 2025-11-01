// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title USDStablecoin
 * @notice Mock USDT for testing (18 decimals)
 * @dev Unrestricted mint for test convenience
 */
contract USDStablecoin is ERC20, Ownable {
    constructor() ERC20("Tether USD", "USDT") Ownable(msg.sender) {}

    /// @notice Mint tokens (unrestricted for testing)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Batch mint to multiple recipients (owner only)
     * @param recipients Addresses to receive tokens
     * @param amount Amount per recipient
     */
    function preMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
