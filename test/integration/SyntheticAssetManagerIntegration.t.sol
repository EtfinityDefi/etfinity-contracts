// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/SyntheticAssetManager.sol";
import "../../contracts/interfaces/IChainlinkAggregator.sol";

/**
 * @title SyntheticAssetManagerIntegrationTest
 * @dev Integration tests for the SyntheticAssetManager contract using a forked Sepolia network.
 * These tests interact with actual deployed contracts on Sepolia to replicate real-world scenarios.
 */
contract SyntheticAssetManagerIntegrationTest is Test {
    // Contract Instances for the forked Sepolia network
    SyntheticAssetManager public forkedManager;
    IERC20 public forkedUSDC;
    IERC20 public forkedSSPY;
    IChainlinkAggregator public forkedSPYPriceFeed;
    IChainlinkAggregator public forkedUSDCPriceFeed;

    // Test account simulating the user's MetaMask wallet
    address public myMetaMaskAddress;

    // Constants for Sepolia Contract Addresses
    // IMPORTANT: Replace these with your actual deployed addresses on Sepolia.
    address public constant SEPOLIA_ETFINITY_PROTOCOL_ADDRESS =
        0xd409DBa507A514974666d51E8102120F66a01dcE;
    address public constant SEPOLIA_USDC_ADDRESS =
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant SEPOLIA_SSPY_ADDRESS =
        0x8267cF9254734C6Eb452a7bb9AAF97B392258b21;
    address public constant SEPOLIA_SPY_PRICE_FEED_ADDRESS =
        0x4b531A318B0e44B549F3b2f824721b3D0d51930A; // CSPX/USD
    address public constant SEPOLIA_USDC_PRICE_FEED_ADDRESS =
        0x14866185B1962B63C3Ea9E03Bc1da838bab34C19; // DAI/USD on Sepolia (used as proxy)

    // Decimal places for tokens on Sepolia
    uint8 public constant USDC_DECIMALS = 6;
    uint8 public constant SSPY_DECIMALS = 18;
    uint8 public constant CHAINLINK_PRICE_DECIMALS = 8; // Common for Chainlink feeds

    /**
     * @dev Sets up the testing environment by forking Sepolia.
     * Instantiates interfaces to interact with existing contracts on the forked network.
     */
    function setUp() public {
        // IMPORTANT: Replace this with your actual MetaMask wallet address.
        myMetaMaskAddress = 0x4CBB583c0d148084de56Fc924732e1c76d0980c3;

        // Instantiate contracts on the forked network
        forkedManager = SyntheticAssetManager(
            SEPOLIA_ETFINITY_PROTOCOL_ADDRESS
        );
        forkedUSDC = IERC20(SEPOLIA_USDC_ADDRESS);
        forkedSSPY = IERC20(SEPOLIA_SSPY_ADDRESS);
        forkedSPYPriceFeed = IChainlinkAggregator(
            SEPOLIA_SPY_PRICE_FEED_ADDRESS
        );
        forkedUSDCPriceFeed = IChainlinkAggregator(
            SEPOLIA_USDC_PRICE_FEED_ADDRESS
        );

        // Provide ETH to your MetaMask address for gas on the fork
        vm.deal(myMetaMaskAddress, 1 ether);

        console.log("--- Sepolia Fork Setup Complete ---");
        console.log("Forked EtfinityProtocol Address:", address(forkedManager));
        console.log("Forked USDC Address:", address(forkedUSDC));
        console.log("Forked sSPY Address:", address(forkedSSPY));
        console.log(
            "Forked SPY Price Feed Address:",
            address(forkedSPYPriceFeed)
        );
        console.log(
            "Forked USDC Price Feed Address (using DAI/USD proxy):",
            address(forkedUSDCPriceFeed)
        );
        console.log("Your MetaMask Address (on fork):", myMetaMaskAddress);
        console.log(
            "Your MetaMask ETH balance (on fork):",
            myMetaMaskAddress.balance
        );
        console.log(
            "Your MetaMask USDC balance (on fork):",
            forkedUSDC.balanceOf(myMetaMaskAddress)
        );
        (, int256 spyPrice, , , ) = forkedSPYPriceFeed.latestRoundData();
        (, int256 usdcPrice, , , ) = forkedUSDCPriceFeed.latestRoundData();
        console.log(
            "Current SPY Price (from real Chainlink on fork):",
            spyPrice
        );
        console.log(
            "Current USDC Price (from real Chainlink DAI/USD on fork):",
            usdcPrice
        );
    }

    /**
     * @dev Tests the mintSPY function on a forked Sepolia network.
     * This test will attempt to replicate the live transaction failure by interacting
     * with the actual deployed contracts and their current state on Sepolia.
     */
    function testMintSPY_OnSepoliaFork() public {
        uint256 usdcAmountToMintWith = 5 * (10 ** USDC_DECIMALS); // 5 USDC

        // Initial State Check (on forked Sepolia)
        uint256 initialUserUSDCBalance = forkedUSDC.balanceOf(
            myMetaMaskAddress
        );
        uint256 initialUserSSPYBalance = forkedSSPY.balanceOf(
            myMetaMaskAddress
        );

        console.log("--- Starting Mint Test on Sepolia Fork ---");
        console.log("Initial MetaMask USDC Balance:", initialUserUSDCBalance);
        console.log("Initial MetaMask sSPY Balance:", initialUserSSPYBalance);
        console.log("Amount of USDC to mint with:", usdcAmountToMintWith);

        // Step 1: Approve the protocol to spend USDC
        vm.startPrank(myMetaMaskAddress);
        forkedUSDC.approve(address(forkedManager), usdcAmountToMintWith);
        vm.stopPrank();

        uint256 currentAllowance = forkedUSDC.allowance(
            myMetaMaskAddress,
            address(forkedManager)
        );
        console.log("Allowance set by MetaMask address:", currentAllowance);
        assertGe(
            currentAllowance,
            usdcAmountToMintWith,
            "Allowance should be sufficient"
        );

        // Step 2: Call mintSPY on the protocol
        // vm.expectRevert(); // Uncomment this line if you expect the transaction to revert
        vm.startPrank(myMetaMaskAddress);
        forkedManager.mintSPY(usdcAmountToMintWith);
        vm.stopPrank();

        // Assertions (if the transaction doesn't revert)
        console.log("Mint transaction successful on fork!");
        console.log(
            "MetaMask USDC balance after mint:",
            forkedUSDC.balanceOf(myMetaMaskAddress)
        );
        console.log(
            "MetaMask sSPY balance after mint:",
            forkedSSPY.balanceOf(myMetaMaskAddress)
        );
    }
}
