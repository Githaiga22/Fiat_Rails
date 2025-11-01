// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/USDStablecoin.sol";
import "../src/CountryToken.sol";
import "../src/UserRegistry.sol";
import "../src/ComplianceManager.sol";
import "../src/MintEscrow.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy
 * @notice Deployment script for FiatRails contracts
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url <RPC> --broadcast --verify
 */
contract Deploy is Script {
    // Deployed contract addresses
    USDStablecoin public usdStablecoin;
    CountryToken public countryToken;
    UserRegistry public userRegistry;
    ComplianceManager public complianceManagerImpl;
    ComplianceManager public complianceManager;
    MintEscrow public mintEscrow;

    bytes32 public constant COUNTRY_CODE = bytes32("KES");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy USDStablecoin
        console.log("\n1. Deploying USDStablecoin...");
        usdStablecoin = new USDStablecoin();
        console.log("USDStablecoin deployed at:", address(usdStablecoin));

        // 2. Deploy CountryToken
        console.log("\n2. Deploying CountryToken...");
        countryToken = new CountryToken();
        console.log("CountryToken deployed at:", address(countryToken));

        // 3. Deploy UserRegistry
        console.log("\n3. Deploying UserRegistry...");
        userRegistry = new UserRegistry();
        console.log("UserRegistry deployed at:", address(userRegistry));

        // 4. Deploy ComplianceManager with UUPS proxy
        console.log("\n4. Deploying ComplianceManager...");
        complianceManagerImpl = new ComplianceManager();
        console.log("ComplianceManager implementation:", address(complianceManagerImpl));

        bytes memory initData = abi.encodeWithSelector(
            ComplianceManager.initialize.selector,
            deployer,
            address(userRegistry)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(complianceManagerImpl), initData);
        complianceManager = ComplianceManager(address(proxy));
        console.log("ComplianceManager proxy:", address(complianceManager));

        // 5. Deploy MintEscrow
        console.log("\n5. Deploying MintEscrow...");
        mintEscrow = new MintEscrow(
            address(usdStablecoin),
            address(countryToken),
            address(userRegistry),
            COUNTRY_CODE
        );
        console.log("MintEscrow deployed at:", address(mintEscrow));

        // 6. Configure roles and permissions
        console.log("\n6. Configuring roles...");

        // Grant MINTER_ROLE to MintEscrow
        countryToken.addMinter(address(mintEscrow));
        console.log("Granted MINTER_ROLE to MintEscrow");

        // Grant COMPLIANCE_OFFICER to deployer and ComplianceManager
        userRegistry.addComplianceOfficer(deployer);
        userRegistry.addComplianceOfficer(address(complianceManager));
        console.log("Granted COMPLIANCE_OFFICER roles");

        // 7. Pre-mint some USD for testing (optional)
        console.log("\n7. Pre-minting USD for testing...");
        usdStablecoin.mint(deployer, 1000000e18); // 1M USDT
        console.log("Minted 1M USDT to deployer");

        vm.stopBroadcast();

        // 8. Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Deployer:", deployer);
        console.log("USDStablecoin:", address(usdStablecoin));
        console.log("CountryToken:", address(countryToken));
        console.log("UserRegistry:", address(userRegistry));
        console.log("ComplianceManager:", address(complianceManager));
        console.log("MintEscrow:", address(mintEscrow));

        // 9. Write deployment addresses to JSON file
        console.log("\n9. Writing deployments.json...");
        string memory json = string.concat(
            '{\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "usdStablecoin": "', vm.toString(address(usdStablecoin)), '",\n',
            '  "countryToken": "', vm.toString(address(countryToken)), '",\n',
            '  "userRegistry": "', vm.toString(address(userRegistry)), '",\n',
            '  "complianceManager": "', vm.toString(address(complianceManager)), '",\n',
            '  "mintEscrow": "', vm.toString(address(mintEscrow)), '",\n',
            '  "network": "lisk-sepolia",\n',
            '  "chainId": 4202,\n',
            '  "timestamp": ', vm.toString(block.timestamp), '\n',
            '}'
        );

        vm.writeFile("../deployments.json", json);
        console.log("Deployment addresses saved to deployments.json");
    }
}
