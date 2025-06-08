// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @dev Interface for Chainlink AggregatorV3 price feeds.
 * This is used to fetch the latest price from a Chainlink oracle.
 * Typically imported from Chainlink's contracts, but provided here for completeness.
 */
interface IChainlinkAggregator {
    /**
     * @dev Returns the latest round data.
     * @return roundId The round ID.
     * @return answer The price of the asset at the given round.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was last updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @dev Returns the number of decimals used by the price feed.
     * This is crucial for correctly scaling the price data.
     */
    function decimals() external view returns (uint8);
}
