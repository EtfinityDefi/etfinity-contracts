// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all necessary contracts for deployment
import "../contracts/SyntheticAssetManager.sol";
import "../contracts/mocks/MockERC20.sol"; // For USDC
import "../contracts/mocks/MockChainlinkAggregator.sol";
import "../contracts/sSPYToken.sol"; // The actual sSPYToken contract

/**
 * @title DeployEtfinity
 * @dev The main deployment script for the entire Etfinity Protocol.
 * This script handles the deployment of all core components:
 * SyntheticAssetManager, sSPYToken, mock collateral token (USDC),
 * and mock Chainlink price feeds.
 *
 * To run this script:
 * 1. Ensure your Anvil instance is running (`anvil`) for local testing.
 * 2. Set your private key and RPC URL environment variables (e.g., in a .env file).
 * Example .env (for Sepolia):
 * SEPOLIA_PRIVATE_KEY=0x...
 * SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
 * ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
 *
 * 3. Execute with Forge:
 * For Sepolia: `forge script script/DeployEtfinity.s.sol --rpc-url sepolia --broadcast --verify -vvvv`
 * For Arbitrum Sepolia: `forge script script/DeployEtfinity.s.sol --rpc-url arbitrumSepolia --broadcast --verify -vvvv`
 */
contract DeployEtfinity is Script {
    // --- Constants for Deployment Parameters ---
    uint256 public constant INITIAL_TARGET_CR = 15000; // 150.00% collateralization ratio (basis points)
    uint256 public constant INITIAL_MIN_CR = 13000; // 130.00% minimum collateralization ratio (basis points)
    uint256 public constant INITIAL_LIQUIDATION_BONUS = 500; // 5.00% liquidation bonus (basis points)

    // Mock Chainlink price feed values, scaled by 10**8 as is typical.
    uint256 public constant SPY_PRICE_NORMAL = 5200 * 10 ** 8; // $5200 per synthetic asset unit
    uint256 public constant USDC_PRICE_NORMAL = 1 * 10 ** 8; // $1.00 per collateral asset unit

    // Decimal places for mock tokens and price feeds.
    uint8 public constant SSPY_DECIMALS = 18;
    uint8 public constant USDC_DECIMALS = 6;
    uint8 public constant CHAINLINK_PRICE_DECIMALS = 8;

    // Stores the addresses of the deployed contracts
    address public syntheticAssetManagerAddress;
    address public sspyTokenAddress;
    address public usdcTokenAddress;
    address public spyPriceFeedAddress;
    address public usdcPriceFeedAddress;

    function run() public returns (address) {
        uint256 deployerPrivateKey;
        string memory privateKeyEnvVar;

        // Determine which private key environment variable to use based on the current chain ID
        if (block.chainid == 11155111) {
            // Sepolia Chain ID
            privateKeyEnvVar = "SEPOLIA_PRIVATE_KEY";
            console.log("Deploying to Sepolia.");
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia Chain ID
            privateKeyEnvVar = "ARBITRUM_SEPOLIA_PRIVATE_KEY";
            console.log("Deploying to Arbitrum Sepolia.");
        } else {
            // Fallback for local development (e.g., Anvil) or other testnets
            privateKeyEnvVar = "PRIVATE_KEY";
            console.log(
                "Deploying to unknown chain, attempting to use generic PRIVATE_KEY."
            );
        }

        // Load deployer's private key. vm.envUint will revert if the variable is not set.
        deployerPrivateKey = vm.envUint(privateKeyEnvVar);
        address payable deployer = payable(vm.addr(deployerPrivateKey));

        // Start broadcasting transactions from the deployer account.
        vm.startBroadcast(deployerPrivateKey);

        console.log("\n--- Deploying Etfinity Protocol Components ---\n");
        console.log("Deployer address:", deployer);
        console.log("Account balance:", deployer.balance);

        // 1. Deploy MockERC20 for USDC collateral
        console.log("-> Deploying MockERC20 for USDC...");
        MockERC20 usdcToken = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        usdcTokenAddress = address(usdcToken);
        console.log("   USDC Token deployed at:", usdcTokenAddress);

        // 2. Deploy MockChainlinkAggregator price feeds
        console.log("-> Deploying MockChainlinkAggregator price feeds...");
        MockChainlinkAggregator spyPriceFeed = new MockChainlinkAggregator(
            int256(SPY_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );
        MockChainlinkAggregator usdcPriceFeed = new MockChainlinkAggregator(
            int256(USDC_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );
        spyPriceFeedAddress = address(spyPriceFeed);
        usdcPriceFeedAddress = address(usdcPriceFeed);
        console.log("   SPY Price Feed deployed at:", spyPriceFeedAddress);
        console.log("   USDC Price Feed deployed at:", usdcPriceFeedAddress);

        // 3. Deploy the actual sSPYToken contract
        console.log(
            "-> Deploying sSPYToken (real contract) with deployer as initial minter..."
        );
        sSPYToken sspyToken = new sSPYToken(deployer); // Deployer temporarily gets MINTER_ROLE
        sspyTokenAddress = address(sspyToken);
        console.log("   sSPYToken deployed at:", sspyTokenAddress);

        // 4. Deploy the SyntheticAssetManager contract
        console.log("-> Deploying SyntheticAssetManager...");
        SyntheticAssetManager manager = new SyntheticAssetManager(
            sspyTokenAddress,
            usdcTokenAddress,
            spyPriceFeedAddress,
            usdcPriceFeedAddress,
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );
        syntheticAssetManagerAddress = address(manager);
        console.log(
            "   SyntheticAssetManager deployed at:",
            syntheticAssetManagerAddress
        );

        // 5. Grant MINTER_ROLE on sSPYToken to the SyntheticAssetManager
        console.log(
            "-> Granting MINTER_ROLE on sSPYToken to SyntheticAssetManager..."
        );
        sspyToken.grantRole(
            sspyToken.MINTER_ROLE(),
            syntheticAssetManagerAddress
        );
        console.log(
            "   MINTER_ROLE granted to SyntheticAssetManager on sSPYToken."
        );

        console.log("\n--- Etfinity Protocol Deployment Complete ---\n");

        // Stop broadcasting transactions.
        vm.stopBroadcast();

        // Return the address of the main deployed component
        return syntheticAssetManagerAddress;
    }
}
