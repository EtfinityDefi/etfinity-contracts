// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// This interface is used to interact with ERC20 tokens that have a decimals() function.
// OpenZeppelin's IERC20 does not include `decimals()`.
interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}
