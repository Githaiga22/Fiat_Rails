// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ComplianceManager.sol";
import "../src/UserRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ComplianceManagerTest
 * @notice Test suite for ComplianceManager upgradeable contract
 */
contract ComplianceManagerTest is Test {
    ComplianceManager public implementation;
    ComplianceManager public manager;
    UserRegistry public registry;
    ERC1967Proxy public proxy;

    address public admin;
    address public alice;

    bytes32 public constant COMPLIANCE_OFFICER = keccak256("COMPLIANCE_OFFICER");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        admin = address(this);
        alice = makeAddr("alice");

        registry = new UserRegistry();
        registry.addComplianceOfficer(address(this));

        implementation = new ComplianceManager();
        bytes memory initData = abi.encodeWithSelector(
            ComplianceManager.initialize.selector,
            admin,
            address(registry)
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        manager = ComplianceManager(address(proxy));

        registry.addComplianceOfficer(address(manager));
    }

    function testInitialization() public view {
        assertTrue(manager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(manager.hasRole(COMPLIANCE_OFFICER, admin));
        assertTrue(manager.hasRole(UPGRADER_ROLE, admin));
        assertEq(address(manager.userRegistry()), address(registry));
        assertEq(manager.MAX_RISK_SCORE(), 83);
    }

    function testCannotReinitialize() public {
        vm.expectRevert();
        manager.initialize(alice, address(registry));
    }
}
