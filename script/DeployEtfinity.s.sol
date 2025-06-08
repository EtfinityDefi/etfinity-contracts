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
 * This script now directly handles the deployment of all core components,
 * including the SyntheticAssetManager, sSPYToken, mock collateral token (USDC),
 * and mock Chainlink price feeds.
 *
 * This approach avoids nested script deployments that can hit contract size limits,
 * making the deployment process more robust and efficient.
 *
 * To run this script:
 * 1. Ensure your Anvil instance is running (`anvil`).
 * 2. Set your `PRIVATE_KEY` environment variable (e.g., `export PRIVATE_KEY=0x...`).
 * 3. Execute with Forge: `forge script script/DeployEtfinity.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvvv`
 * (Adjust RPC URL and add `--verify` and `--etherscan-api-key` for testnet/mainnet verification)
 */
contract DeployEtfinity is Script {
    // --- Constants for Deployment Parameters (Mirroring test setup for consistency) ---
    uint256 public constant INITIAL_TARGET_CR = 15000; // 150.00% collateralization ratio
    uint256 public constant INITIAL_MIN_CR = 13000; // 130.00% minimum collateralization ratio
    uint256 public constant INITIAL_LIQUIDATION_BONUS = 500; // 5.00% liquidation bonus

    // Mock Chainlink price feed values, scaled by 10**8 as is typical for Chainlink.
    uint256 public constant SPY_PRICE_NORMAL = 5200 * 10 ** 8; // $5200 per synthetic asset unit.
    uint256 public constant USDC_PRICE_NORMAL = 1 * 10 ** 8; // $1.00 per collateral asset unit.

    // Decimal places for mock tokens and price feeds.
    uint8 public constant SSPY_DECIMALS = 18; // sSPY token decimal places.
    uint8 public constant USDC_DECIMALS = 6; // USDC token decimal places.
    uint8 public constant CHAINLINK_PRICE_DECIMALS = 8; // Chainlink price feed decimal places.

    // Stores the addresses of the deployed contracts
    address public syntheticAssetManagerAddress;
    address public sspyTokenAddress;
    address public usdcTokenAddress;
    address public spyPriceFeedAddress;
    address public usdcPriceFeedAddress;
    // Add more state variables here for other deployed contracts (e.g., CollateralVault)
    // address public collateralVaultAddress;

    function run() public returns (address) {
        // Load deployer's private key and address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Start broadcasting transactions from the deployer account.
        // This single broadcast will cover all deployments and interactions within this script.
        vm.startBroadcast(deployerPrivateKey);

        console.log("\n--- Deploying Etfinity Protocol Components ---\n");

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
        // The sSPYToken constructor grants MINTER_ROLE to the initialMinter (which will be SyntheticAssetManager)
        // Here, we temporarily grant it to the deployer, then transfer to the manager.
        console.log(
            "-> Deploying sSPYToken (real contract) with deployer as initial minter..."
        );
        sSPYToken sspyToken = new sSPYToken(deployer); // Deployer temporarily gets MINTER_ROLE
        sspyTokenAddress = address(sspyToken);
        console.log("   sSPYToken deployed at:", sspyTokenAddress);

        // 4. Deploy the SyntheticAssetManager contract
        console.log("-> Deploying SyntheticAssetManager...");
        SyntheticAssetManager manager = new SyntheticAssetManager(
            sspyTokenAddress, // Pass the real sSPYToken address
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
        // This is done by the deployer (who is admin of sSPYToken and temporarily had MINTER_ROLE).
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

        // --- Deploy other core components of the Etfinity Protocol (EXAMPLES) ---
        // Uncomment and implement these sections as your protocol grows.

        // Example: Deploying a CollateralVault
        // console.log("\n-> Deploying CollateralVault...");
        // CollateralVault collateralVault = new CollateralVault(sspyTokenAddress, syntheticAssetManagerAddress);
        // collateralVaultAddress = address(collateralVault);
        // console.log("   CollateralVault deployed at:", collateralVaultAddress);

        // Example: Granting roles to the CollateralVault on sSPYToken if needed
        // (Note: sSPYToken is imported to access its MINTER_ROLE constant and grantRole function)
        // console.log("-> Granting necessary roles to CollateralVault on sSPYToken...");
        // sspyToken.grantRole(sspyToken.MINTER_ROLE(), collateralVaultAddress);
        // console.log("   Roles granted to CollateralVault.");

        // Example: Deploying another hypothetical Etfinity module
        // console.log("\n-> Deploying AnotherEtfinityModule...");
        // AnotherEtfinityModule anotherModule = new AnotherEtfinityModule(syntheticAssetManagerAddress, sspyTokenAddress);
        // console.log("   AnotherEtfinityModule deployed at:", address(anotherModule));

        console.log("\n--- Etfinity Protocol Deployment Complete ---\n");

        // Stop broadcasting transactions.
        vm.stopBroadcast();

        // Return the address of the main deployed component or the orchestrator itself
        return syntheticAssetManagerAddress;
    }
}
