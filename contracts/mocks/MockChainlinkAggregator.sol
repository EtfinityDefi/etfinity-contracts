// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IChainlinkAggregator.sol";

/**
 * @title MockChainlinkAggregator
 * @dev A mock Chainlink AggregatorV3Interface for testing purposes.
 * This contract allows setting arbitrary price and decimals for simulating oracle feeds.
 */
contract MockChainlinkAggregator is
    IChainlinkAggregator // Explicitly inherit the interface
{
    int256 private s_answer;
    uint8 private s_decimals;
    uint256 private s_updatedAt;
    uint80 private s_roundId;

    /**
     * @dev Constructor for the mock aggregator.
     * @param initialAnswer The initial price to return.
     * @param initialDecimals The number of decimals for the price.
     */
    constructor(int256 initialAnswer, uint8 initialDecimals) {
        s_answer = initialAnswer;
        s_decimals = initialDecimals;
        s_updatedAt = block.timestamp;
        s_roundId = 1; // Start with round ID 1
    }

    /**
     * @dev Sets a new answer (price) for the mock oracle.
     * @param newAnswer The new price to be returned by latestRoundData().
     */
    function setAnswer(int256 newAnswer) external {
        s_answer = newAnswer;
        s_updatedAt = block.timestamp; // Update timestamp when answer changes
        s_roundId++; // Increment round ID
    }

    /**
     * @dev Sets a new decimals value for the mock oracle.
     * @param newDecimals The new decimals value.
     */
    function setDecimals(uint8 newDecimals) external {
        s_decimals = newDecimals;
    }

    /**
     * @dev Implements the latestRoundData function from IChainlinkAggregator.
     * Returns the mocked price data.
     */
    function latestRoundData()
        external
        view
        override
        returns (
            // Mark as override since it implements an interface function
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt, // Corrected from uint256 to uint80 to match Chainlink's standard
            uint80 answeredInRound
        )
    {
        roundId = s_roundId;
        answer = s_answer;
        startedAt = s_updatedAt; // For simplicity, using updatedAt as startedAt
        updatedAt = uint80(s_updatedAt); // Cast to uint80 to match interface
        answeredInRound = s_roundId;
    }

    /**
     * @dev Implements the decimals function from IChainlinkAggregator.
     * Returns the mocked decimals value.
     */
    function decimals() external view override returns (uint8) {
        return s_decimals;
    }
}
