// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/helpers/Constants.sol";

contract PriceOracle is Ownable {
    mapping(address => address) public priceFeeds;

    function addPriceFeed(
        address[] calldata _tokens,
        address[] calldata _priceFeeds
    ) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            priceFeeds[_tokens[i]] = _priceFeeds[i];
        }
    }

    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view returns (uint256) {
        return amount * getLastPrice(tokenFrom, tokenTo);
    }

    // tokenFrom price / tokenTo Price
    function getLastPrice(address tokenFrom, address tokenTo)
        public
        view
        returns (uint256)
    {
        if (tokenFrom == tokenTo) return Constants.WAD;

        return (Constants.WAD * (_getPrice(tokenFrom))) / (_getPrice(tokenTo));
    }

    function _getPrice(address token) internal view returns (uint256) {
        require(priceFeeds[token] != address(0), "PO_PRICE_FEED_DOESNT_EXIST"); // T:[PO-9]

        /**
            function latestRoundData() external view
                returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
                );
        */
        (
            ,
            int256 price, //uint startedAt, //uint timeStamp, //uint80 answeredInRound
            ,
            ,

        ) = AggregatorV3Interface(priceFeeds[token]).latestRoundData();
        return uint256(price);
    }
}
