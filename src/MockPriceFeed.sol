// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    error Unauthorised();

    int256 private _exchangeRate;
    address private immutable _owner;
    uint8 private immutable _decimals;

    constructor(int256 exchangeRate, uint8 __decimals) {
        _exchangeRate = exchangeRate;
        _owner = msg.sender;
        _decimals = __decimals;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "DAI/ETH";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function modifyExchangeRate(int256 exchangeRate) external {
        if (msg.sender != _owner) revert Unauthorised();

        _exchangeRate = exchangeRate;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
        return (
            _roundId,
            _exchangeRate,
            0,
            0,
            1
        );
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
        return (
            1,
            _exchangeRate,
            0,
            0,
            1
        );
    }
}