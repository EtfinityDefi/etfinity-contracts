// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Used for initial setup logging, consider removing for final production tests.
import "../contracts/SyntheticAssetManager.sol";
import "../contracts/sSPYToken.sol"; // Import the specific sSPYToken contract
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockChainlinkAggregator.sol";

// --- Custom Errors from OpenZeppelin Contracts (for expectRevert) ---
// These are standard errors often thrown by OpenZeppelin's AccessControl and Pausable modules.
error AccessControlUnauthorizedAccount(address account, bytes32 role);
error EnforcedPause();

// --- Custom Errors from SyntheticAssetManager (for expectRevert) ---
// IMPORTANT: These error definitions MUST exactly match those in your SyntheticAssetManager.sol contract
// in terms of name and parameter types.
error InvalidZeroAddress();
error InvalidAmount();
error InvalidCollateralRatio(uint256 currentRatio, uint256 requiredRatio);
error InsufficientAllowance(address owner, uint256 spender, uint256 amount); // Matches contract: owner, spender, amount
error InsufficientFunds(address owner, uint256 available, uint256 required); // Matches contract: owner, available, required
error OracleDataStale(); // Defined in contract, but not explicitly tested here
error OracleDataInvalid();
error LiquidationNotAllowed(string reason);
error LiquidationAmountTooLarge();
error CollateralCalculationError();
error PriceFeedNotSet(); // Matches contract: no parameters

/**
 * @title SyntheticAssetManagerTest
 * @dev Comprehensive unit tests for the SyntheticAssetManager contract using Forge.
 * Each test focuses on a specific function or scenario to ensure correctness, robustness,
 * and adherence to defined business logic and security principles.
 */
contract SyntheticAssetManagerTest is Test {
    // --- Contract Instances ---
    // These variables will hold instances of the contracts being tested or mocked.
    SyntheticAssetManager public manager;
    MockERC20 public sspy; // Mock synthetic asset token (e.g., sSPY)
    MockERC20 public usdc; // Mock collateral token (e.g., USDC), with 6 decimals.
    MockChainlinkAggregator public spyPriceFeed; // Mock Chainlink Aggregator for S&P 500 price.
    MockChainlinkAggregator public usdcPriceFeed; // Mock Chainlink Aggregator for collateral token price (e.g., USDC/USD).

    // --- Test Accounts ---
    // Dedicated addresses for simulating different user roles and interactions.
    address public deployer; // Account responsible for contract deployment and initial admin roles.
    address public user1; // Primary user for general contract interactions (minting, redeeming).
    address public user2; // Secondary user, available for multi-user scenarios.
    address public liquidator; // Account designated for testing liquidation processes.
    address public admin; // Alias for deployer, holds DEFAULT_ADMIN_ROLE.
    address public oracleAdmin; // Alias for deployer, holds ORACLE_ADMIN_ROLE.

    // --- Constants for Test Setup ---
    // Predefined values used across tests for consistency and clarity.
    uint256 public constant INITIAL_USDC_MINT = 10_000_000 * 10 ** 6; // 10,000,000 USDC, assuming 6 decimals.
    uint256 public constant INITIAL_ETH_DEAL = 10 ether; // Sufficient ETH for gas fees for test accounts.

    // Initial contract parameters configured during deployment.
    uint256 public constant INITIAL_TARGET_CR = 15000; // 150.00% collateralization ratio (15000 basis points).
    uint256 public constant INITIAL_MIN_CR = 13000; // 130.00% minimum collateralization ratio (13000 basis points).
    uint256 public constant INITIAL_LIQUIDATION_BONUS = 500; // 5.00% liquidation bonus (500 basis points).

    // Mock Chainlink price feed values. Typically scaled by 10**8 as is common for Chainlink.
    uint256 public constant SPY_PRICE_NORMAL = 5200 * 10 ** 8; // $5200 per synthetic asset unit.
    uint256 public constant USDC_PRICE_NORMAL = 1 * 10 ** 8; // $1.00 per collateral asset unit.

    // Decimal places for mock tokens and price feeds. Essential for accurate scaling in calculations.
    uint8 public constant SSPY_DECIMALS = 18; // sSPY token decimal places.
    uint8 public constant USDC_DECIMALS = 6; // USDC token decimal places.
    uint8 public constant CHAINLINK_PRICE_DECIMALS = 8; // Chainlink price feed decimal places.

    /**
     * @dev Sets up the testing environment before each test function.
     * This involves initializing test accounts, deploying mock tokens and price feeds,
     * and deploying the SyntheticAssetManager contract with predefined parameters.
     */
    function setUp() public {
        // --- Initialize Test Accounts and Provide ETH ---
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidator = makeAddr("liquidator");
        admin = deployer; // Deployer is assigned the DEFAULT_ADMIN_ROLE.
        oracleAdmin = deployer; // Deployer is assigned the ORACLE_ADMIN_ROLE.

        // Distribute ETH to accounts for gas fees.
        vm.deal(deployer, INITIAL_ETH_DEAL);
        vm.deal(user1, INITIAL_ETH_DEAL);
        vm.deal(user2, INITIAL_ETH_DEAL);
        vm.deal(liquidator, INITIAL_ETH_DEAL);

        // --- Deploy Mock ERC20 Tokens ---
        // Deploy USDC (collateral token) and sSPY (synthetic asset token).
        vm.startPrank(deployer); // Deploy as 'deployer' account.
        usdc = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        sspy = new MockERC20("Synthetic SPY", "sSPY", SSPY_DECIMALS); // Using MockERC20 for sSPY
        vm.stopPrank();

        // Mint initial USDC to test users for minting and liquidation scenarios.
        usdc.mint(user1, INITIAL_USDC_MINT);
        usdc.mint(liquidator, INITIAL_USDC_MINT);

        // --- Deploy Mock Chainlink Aggregators ---
        // Initialize price feeds with normal, predefined prices.
        spyPriceFeed = new MockChainlinkAggregator(
            int256(SPY_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );
        usdcPriceFeed = new MockChainlinkAggregator(
            int256(USDC_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );

        // --- Deploy SyntheticAssetManager Contract ---
        // Deploy the main contract, passing in addresses of mock dependencies and initial parameters.
        vm.startPrank(deployer);
        manager = new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );
        vm.stopPrank();

        // --- Log Initial Setup Details (for debugging/visibility during test runs) ---
        console.log("--- Initial Setup Complete ---");
        console.log("sSPYToken Address:", address(sspy));
        console.log("Collateral Token (USDC) Address:", address(usdc));
        console.log("SyntheticAssetManager Address:", address(manager));
        console.log("Deployer (Admin) Address:", deployer);
        console.log("User1 Address:", user1);
        console.log("User2 Address:", user2);
        console.log("Liquidator Address:", liquidator);
        console.log("User1 USDC balance:", usdc.balanceOf(user1));
    }

    /**
     * @dev Helper function to calculate the expected collateral amount returned during sSPY redemption.
     * This calculation mirrors the internal logic of the SyntheticAssetManager's `redeemSPY` function
     * to ensure consistency in test assertions. It uses the manager's internal price getters.
     *
     * @param sspyAmountToRedeem The amount of sSPY that is being redeemed.
     * @return The calculated collateral amount that should be returned.
     */
    function calculateCollateralReturn(
        uint256 sspyAmountToRedeem
    ) public view returns (uint256) {
        // Fetch current prices from mock price feeds using the manager's internal getters.
        uint256 spyPrice = manager._getSPYPriceRaw();
        uint256 collateralPrice = manager._getCollateralPriceRaw();

        // Retrieve decimal places from the manager for precise calculations.
        uint8 sspyDecimals_ = manager.sspyDecimals();
        uint8 collateralDecimals_ = manager.collateralDecimals();
        uint8 spyPriceDecimals_ = manager.spyPriceDecimals();
        uint8 collateralPriceDecimals_ = manager.collateralPriceDecimals();

        // Convert sSPY amount to its USD value, using 18 decimal precision for intermediate calculations.
        // This maintains accuracy across different token and price feed decimal places.
        uint256 sspyValueUSD = (sspyAmountToRedeem * spyPrice * (10 ** 18)) /
            ((10 ** sspyDecimals_) * (10 ** spyPriceDecimals_));

        // Convert collateral price to its USD value, also using 18 decimal precision.
        uint256 collateralPriceUSDValue = (collateralPrice * (10 ** 18)) /
            (10 ** collateralPriceDecimals_);

        // Convert the USD value back to the collateral token amount.
        uint256 collateralToReturn = (sspyValueUSD *
            (10 ** collateralDecimals_)) / collateralPriceUSDValue;

        return collateralToReturn;
    }

    // --- Test Suite: Constructor and Initialization ---

    /**
     * @dev Tests successful deployment of `SyntheticAssetManager` and verifies
     * that all constructor parameters (token addresses, price feed addresses,
     * and initial ratios) are correctly set. Also checks initial role assignments.
     */
    function testConstructor_Success() public view {
        assertEq(
            address(manager._sSPYToken()),
            address(sspy),
            "sSPYToken address not set correctly"
        );
        assertEq(
            address(manager.collateralToken()),
            address(usdc),
            "CollateralToken address not set correctly"
        );
        assertEq(
            address(manager.sSPYPriceFeed()),
            address(spyPriceFeed),
            "SPY price feed not set correctly"
        );
        assertEq(
            address(manager.collateralPriceFeed()),
            address(usdcPriceFeed),
            "Collateral price feed not set correctly"
        );
        assertEq(
            manager.TARGET_COLLATERALIZATION_RATIO(),
            INITIAL_TARGET_CR,
            "Target CR not set correctly"
        );
        assertEq(
            manager.MIN_COLLATERALIZATION_RATIO(),
            INITIAL_MIN_CR,
            "Min CR not set correctly"
        );
        assertEq(
            manager.LIQUIDATION_BONUS_RATIO(),
            INITIAL_LIQUIDATION_BONUS,
            "Liquidation bonus not set correctly"
        );

        // Verify initial roles: deployer should be default admin and oracle admin.
        assertTrue(
            manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), deployer),
            "Deployer should have DEFAULT_ADMIN_ROLE"
        );
        assertTrue(
            manager.hasRole(manager.ORACLE_ADMIN_ROLE(), deployer),
            "Deployer should have ORACLE_ADMIN_ROLE"
        );

        // Verify that stored decimal values from price feeds/tokens are correct.
        assertEq(
            manager.sspyDecimals(),
            SSPY_DECIMALS,
            "sSPY decimals mismatch"
        );
        assertEq(
            manager.collateralDecimals(),
            USDC_DECIMALS,
            "Collateral decimals mismatch"
        );
        assertEq(
            manager.spyPriceDecimals(),
            CHAINLINK_PRICE_DECIMALS,
            "SPY price decimals mismatch"
        );
        assertEq(
            manager.collateralPriceDecimals(),
            CHAINLINK_PRICE_DECIMALS,
            "Collateral price decimals mismatch"
        );
    }

    /**
     * @dev Tests that the constructor reverts with `InvalidZeroAddress`
     * if any critical dependency address (sSPY, collateral, or price feeds) is `address(0)`.
     */
    function testConstructor_RevertsOnZeroAddress() public {
        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(0),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );

        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(0),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );

        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(0),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );

        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(0),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );
    }

    /**
     * @dev Tests that the constructor reverts with `InvalidAmount`
     * if initial collateralization ratios (target CR, min CR) or liquidation bonus are set to zero.
     */
    function testConstructor_RevertsOnZeroRatios() public {
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            0,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        ); // Target CR is zero

        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            0,
            INITIAL_LIQUIDATION_BONUS
        ); // Min CR is zero

        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            0
        ); // Liquidation Bonus is zero
    }

    /**
     * @dev Tests that the constructor reverts with `InvalidCollateralRatio`
     * if `MIN_COLLATERALIZATION_RATIO` is greater than or equal to `TARGET_COLLATERALIZATION_RATIO`.
     * The `InvalidCollateralRatio` error includes the `currentRatio` and `requiredRatio` as arguments.
     */
    function testConstructor_RevertsOnMinGreaterThanTargetCR() public {
        uint256 testTargetCR = INITIAL_TARGET_CR;

        // Case 1: Min CR is equal to Target CR (should revert).
        uint256 testMinCR_Equal = INITIAL_TARGET_CR;
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                testMinCR_Equal, // The value passed as `_minCR` (currentRatio in error)
                testTargetCR // The value passed as `_targetCR` (requiredRatio in error)
            )
        );
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            testTargetCR,
            testMinCR_Equal,
            INITIAL_LIQUIDATION_BONUS
        );

        // Case 2: Min CR is greater than Target CR (should revert).
        uint256 testMinCR_Greater = INITIAL_TARGET_CR + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                testMinCR_Greater, // The value passed as `_minCR` (currentRatio in error)
                testTargetCR // The value passed as `_targetCR` (requiredRatio in error)
            )
        );
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(usdcPriceFeed),
            testTargetCR,
            testMinCR_Greater,
            INITIAL_LIQUIDATION_BONUS
        );
    }

    // --- Test Suite: Admin Functionality ---

    /**
     * @dev Tests successful update of price feed addresses by an authorized admin.
     * Verifies that the new price feed addresses are correctly set and the `OracleAddressUpdated` event is emitted.
     * The `OracleAddressUpdated` event has `oldSPYOracle` and `newSPYOracle` as indexed parameters.
     */
    function testUpdatePriceFeeds_Success() public {
        vm.startPrank(oracleAdmin); // Perform action as `oracleAdmin`.
        MockChainlinkAggregator newSpyFeed = new MockChainlinkAggregator(
            int256(SPY_PRICE_NORMAL + 100),
            CHAINLINK_PRICE_DECIMALS
        );
        MockChainlinkAggregator newUSDCFeed = new MockChainlinkAggregator(
            int256(USDC_PRICE_NORMAL + 1),
            CHAINLINK_PRICE_DECIMALS
        );

        // Expect the `OracleAddressUpdated` event.
        // The first two booleans are true because `oldSPYOracle` and `newSPYOracle` are indexed.
        vm.expectEmit(true, true, false, false);
        emit SyntheticAssetManager.OracleAddressUpdated(
            address(spyPriceFeed), // oldSPYOracle (indexed)
            address(newSpyFeed), // newSPYOracle (indexed)
            address(usdcPriceFeed), // oldCollateralOracle
            address(newUSDCFeed) // newCollateralOracle
        );

        manager.updatePriceFeeds(address(newSpyFeed), address(newUSDCFeed));

        assertEq(
            address(manager.sSPYPriceFeed()),
            address(newSpyFeed),
            "SPY price feed was not updated correctly"
        );
        assertEq(
            address(manager.collateralPriceFeed()),
            address(newUSDCFeed),
            "Collateral price feed was not updated correctly"
        );
        assertEq(
            manager.spyPriceDecimals(),
            CHAINLINK_PRICE_DECIMALS,
            "New SPY price decimals mismatch"
        );
        assertEq(
            manager.collateralPriceDecimals(),
            CHAINLINK_PRICE_DECIMALS,
            "New Collateral price decimals mismatch"
        );

        vm.stopPrank();
    }

    /**
     * @dev Tests that `updatePriceFeeds` reverts with `AccessControlUnauthorizedAccount`
     * when called by an account that does not possess the `ORACLE_ADMIN_ROLE`.
     */
    function testUpdatePriceFeeds_RevertsUnauthorized() public {
        vm.startPrank(user1); // Attempt action as `user1` (unauthorized).
        MockChainlinkAggregator newSpyFeed = new MockChainlinkAggregator(
            int256(SPY_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );
        MockChainlinkAggregator newUSDCFeed = new MockChainlinkAggregator(
            int256(USDC_PRICE_NORMAL),
            CHAINLINK_PRICE_DECIMALS
        );

        // Expect the `AccessControlUnauthorizedAccount` error.
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1, // The account attempting the unauthorized action
                manager.ORACLE_ADMIN_ROLE() // The required role
            )
        );
        manager.updatePriceFeeds(address(newSpyFeed), address(newUSDCFeed));
        vm.stopPrank();
    }

    /**
     * @dev Tests successful update of collateralization ratios by an authorized admin.
     * Verifies that the new ratios are correctly set and the `CollateralizationRatioUpdated` event is emitted.
     * This event has no indexed parameters.
     */
    function testUpdateCollateralizationRatios_Success() public {
        vm.startPrank(admin); // Perform action as `admin`.
        uint256 newTargetCR = 16000;
        uint256 newMinCR = 14000;

        // Expect the `CollateralizationRatioUpdated` event. No indexed parameters.
        vm.expectEmit(false, false, false, false); // Corrected flags: All parameters are non-indexed.
        emit SyntheticAssetManager.CollateralizationRatioUpdated(
            INITIAL_TARGET_CR, // oldTargetRatio
            newTargetCR, // newTargetRatio
            INITIAL_MIN_CR, // oldMinRatio
            newMinCR // newMinRatio
        );

        manager.updateCollateralizationRatios(newTargetCR, newMinCR);
        assertEq(
            manager.TARGET_COLLATERALIZATION_RATIO(),
            newTargetCR,
            "Target CR was not updated correctly"
        );
        assertEq(
            manager.MIN_COLLATERALIZATION_RATIO(),
            newMinCR,
            "Min CR was not updated correctly"
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests that `updateCollateralizationRatios` reverts with `InvalidAmount` or
     * `InvalidCollateralRatio` for invalid input scenarios:
     * - New target/min CR being zero.
     * - New min CR being greater than or equal to new target CR.
     */
    function testUpdateCollateralizationRatios_RevertsInvalidRatios() public {
        vm.startPrank(admin); // Perform actions as `admin`.

        // Test 1: New target CR is zero.
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        manager.updateCollateralizationRatios(0, 14000);

        // Test 2: New min CR is zero.
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        manager.updateCollateralizationRatios(15000, 0);

        // Test 3: New min CR is equal to new target CR (should revert).
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                15000, // currentRatio (newMinCR)
                15000 // requiredRatio (newTargetCR)
            )
        );
        manager.updateCollateralizationRatios(15000, 15000);

        // Test 4: New min CR is greater than new target CR (should revert).
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                16000, // currentRatio (newMinCR)
                15000 // requiredRatio (newTargetCR)
            )
        );
        manager.updateCollateralizationRatios(15000, 16000);
        vm.stopPrank();
    }

    /**
     * @dev Tests that `updateCollateralizationRatios` reverts with `AccessControlUnauthorizedAccount`
     * when called by an account that does not have the `DEFAULT_ADMIN_ROLE`.
     */
    function testUpdateCollateralizationRatios_RevertsUnauthorized() public {
        vm.startPrank(user1); // Attempt action as `user1` (unauthorized).
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1, // The account attempting the unauthorized action
                manager.DEFAULT_ADMIN_ROLE() // The required role
            )
        );
        manager.updateCollateralizationRatios(16000, 14000);
        vm.stopPrank();
    }

    /**
     * @dev Tests successful update of liquidation bonus by an authorized admin.
     * Verifies that the new bonus is correctly set and the `LiquidationBonusUpdated` event is emitted.
     * This event has no indexed parameters.
     */
    function testUpdateLiquidationBonus_Success() public {
        vm.startPrank(admin); // Perform action as `admin`.
        uint256 newBonus = 750;

        // Expect the `LiquidationBonusUpdated` event. No indexed parameters.
        vm.expectEmit(false, false, false, false); // Corrected flags: All parameters are non-indexed.
        emit SyntheticAssetManager.LiquidationBonusUpdated(
            INITIAL_LIQUIDATION_BONUS, // oldBonus
            newBonus // newBonus
        );

        manager.updateLiquidationBonus(newBonus);
        assertEq(
            manager.LIQUIDATION_BONUS_RATIO(),
            newBonus,
            "Liquidation bonus was not updated correctly"
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests that `updateLiquidationBonus` reverts with `InvalidAmount`
     * when a zero bonus amount is provided.
     */
    function testUpdateLiquidationBonus_RevertsOnZeroAmount() public {
        vm.startPrank(admin); // Perform action as `admin`.
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        manager.updateLiquidationBonus(0);
        vm.stopPrank();
    }

    /**
     * @dev Tests that `updateLiquidationBonus` reverts with `AccessControlUnauthorizedAccount`
     * when called by an unauthorized account.
     */
    function testUpdateLiquidationBonus_RevertsUnauthorized() public {
        vm.startPrank(user1); // Attempt action as `user1` (unauthorized).
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1, // The account attempting the unauthorized action
                manager.DEFAULT_ADMIN_ROLE() // The required role
            )
        );
        manager.updateLiquidationBonus(750);
        vm.stopPrank();
    }

    /**
     * @dev Tests successful pausing of the contract by an authorized admin.
     * Verifies that the `paused` state is set to true.
     */
    function testPause_Success() public {
        vm.startPrank(admin); // Perform action as `admin`.
        manager.pause();
        assertTrue(manager.paused(), "Contract should be paused");
        vm.stopPrank();
    }

    /**
     * @dev Tests that `pause` reverts with `AccessControlUnauthorizedAccount`
     * when called by an account that does not possess the `DEFAULT_ADMIN_ROLE`.
     */
    function testPause_RevertsWhenNotAdmin() public {
        vm.startPrank(user1); // Attempt action as `user1` (unauthorized).
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1, // The account attempting the unauthorized action
                manager.DEFAULT_ADMIN_ROLE() // The required role
            )
        );
        manager.pause();
        vm.stopPrank();
    }

    /**
     * @dev Tests successful unpausing of the contract by an authorized admin.
     * Verifies that the `paused` state is set to false after a prior pause.
     */
    function testUnpause_Success() public {
        vm.startPrank(admin); // Perform actions as `admin`.
        manager.pause(); // Pause the contract first.
        manager.unpause(); // Then unpause it.
        assertFalse(manager.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    /**
     * @dev Tests that `unpause` reverts with `AccessControlUnauthorizedAccount`
     * when called by an account that does not possess the `DEFAULT_ADMIN_ROLE`.
     */
    function testUnpause_RevertsWhenNotAdmin() public {
        vm.startPrank(admin); // Perform actions as `admin`.
        manager.pause(); // Ensure the contract is paused for this test case.
        vm.stopPrank();

        vm.startPrank(user1); // Attempt action as `user1` (unauthorized).
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1, // The account attempting the unauthorized action
                manager.DEFAULT_ADMIN_ROLE() // The required role
            )
        );
        manager.unpause();
        vm.stopPrank();
    }

    // --- Test Suite: Minting Functionality (`mintSPY`) ---

    /**
     * @dev Tests successful minting of sSPY by a user.
     * Verifies:
     * - Correct transfer of collateral to the manager.
     * - Correct minting of sSPY to the user.
     * - Accurate updates to user's collateral and debt records.
     * - Correct total supply updates for sSPY.
     * - The `SPYMinted` event is emitted with precise values.
     * - The resulting collateralization ratio is healthy (at or above target).
     */
    function testMintSPY_Success() public {
        uint256 collateralAmount = 1000 * 10 ** USDC_DECIMALS; // Amount of USDC collateral to provide.

        // 1. Calculate the expected amount of sSPY to be minted by the contract.
        uint256 expectedSPYToMint = manager.calculateMintAmount(
            collateralAmount
        );

        // 2. Predict the user's state (collateral and debt) after the mint operation.
        // We add to existing `userCollateral` and `userDebt` in case a user has prior positions.
        uint256 expectedUserCollateralAfterMint = manager.userCollateral(
            user1
        ) + collateralAmount;
        uint256 expectedUserDebtAfterMint = manager.userDebt(user1) +
            expectedSPYToMint;

        // 3. Predict the exact collateralization ratio that the contract will calculate and emit.
        uint256 expectedCollateralRatioAfterMint = manager
            ._calculateCollateralRatio(
                expectedUserCollateralAfterMint,
                expectedUserDebtAfterMint
            );

        // User approves the manager contract to transfer their USDC collateral.
        vm.prank(user1); // Impersonate `user1` for the `approve` call.
        usdc.approve(address(manager), collateralAmount);

        // Expect the `SPYMinted` event to be emitted with the predicted values.
        // The first boolean is true because `user` is an indexed parameter in the event.
        vm.expectEmit(true, false, false, false);
        emit SyntheticAssetManager.SPYMinted(
            user1, // user (indexed)
            collateralAmount, // collateralAmount
            expectedSPYToMint, // sspyMinted
            expectedCollateralRatioAfterMint // collateralRatio
        );

        uint256 initialUSDCBalance = usdc.balanceOf(user1);
        uint256 initialSSPYSUPPLY = sspy.totalSupply();

        // Perform the minting operation as `user1`.
        vm.prank(user1); // Impersonate `user1` for the `mintSPY` call.
        manager.mintSPY(collateralAmount);

        // Assert final state and balances.
        assertEq(
            usdc.balanceOf(user1),
            initialUSDCBalance - collateralAmount,
            "User1 USDC balance incorrect after mint"
        );
        assertEq(
            usdc.balanceOf(address(manager)),
            collateralAmount,
            "Manager USDC balance incorrect after mint"
        );
        assertEq(
            sspy.balanceOf(user1),
            expectedSPYToMint,
            "User1 sSPY balance incorrect after mint"
        );
        assertEq(
            sspy.totalSupply(),
            initialSSPYSUPPLY + expectedSPYToMint,
            "sSPY total supply incorrect after mint"
        );
        assertEq(
            manager.userCollateral(user1),
            expectedUserCollateralAfterMint,
            "User collateral record incorrect after mint"
        ); // Used expected value for consistency
        assertEq(
            manager.userDebt(user1),
            expectedUserDebtAfterMint,
            "User debt record incorrect after mint"
        ); // Used expected value for consistency

        // Verify that the user's collateralization ratio is at or above the target after a successful mint.
        uint256 currentRatio = manager._getCurrentCollateralRatio(user1);
        assertTrue(
            currentRatio >= INITIAL_TARGET_CR,
            "Collateral ratio should be at or above target after mint"
        );
    }

    /**
     * @dev Tests that `mintSPY` reverts with `InvalidAmount` when a zero collateral amount is provided.
     */
    function testMintSPY_RevertsOnZeroAmount() public {
        vm.prank(user1); // Impersonate `user1`.
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        manager.mintSPY(0);
    }

    /**
     * @dev Tests that `mintSPY` reverts with `ERC20InsufficientAllowance` if the
     * `SyntheticAssetManager` contract does not have sufficient allowance to transfer
     * the required collateral from the user's balance.
     * This error originates from the underlying ERC20 token's `transferFrom` function.
     */
    function testMintSPY_RevertsOnInsufficientAllowance() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        // Approve less than required from user1 to the manager.
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount - 1); // User approves less than needed.

        // Expect the ERC20InsufficientAllowance error from the MockERC20 contract.
        // The arguments are: `spender` (the address calling transferFrom, which is manager),
        // `allowance` (what was actually approved), and `needed` (what was requested).
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(manager), // The `spender` is the SyntheticAssetManager contract.
                collateralAmount - 1, // The allowance that was set (less than required).
                collateralAmount // The amount of collateral the manager tried to transfer.
            )
        );
        // Attempt the mint operation as user1; this should now revert.
        vm.prank(user1);
        manager.mintSPY(collateralAmount);
    }

    /**
     * @dev Tests that `mintSPY` reverts with `ERC20InsufficientBalance` if the
     * user does not have enough collateral tokens in their balance, even if allowance is granted.
     * The `mintSPY` function relies on the underlying ERC20 `transferFrom` to handle this.
     */
    function testMintSPY_RevertsOnInsufficientFunds() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS); // Amount user attempts to mint with.

        // Adjust user1's USDC balance to be exactly one unit less than the amount required.
        // This ensures the MockERC20's `transferFrom` will revert with `ERC20InsufficientBalance`.
        uint256 amountToTransferOut = usdc.balanceOf(user1) -
            (collateralAmount - 1);
        if (amountToTransferOut > 0) {
            vm.prank(user1); // Prank user1 for this transfer
            usdc.transfer(user2, amountToTransferOut); // Transfer excess to user2
        }

        // Verify the user's balance is now as expected (for debugging purposes).
        uint256 user1ActualBalance = usdc.balanceOf(user1);
        console.log(
            "User1's USDC balance before mint attempt:",
            user1ActualBalance
        );
        console.log("Collateral amount required for mint:", collateralAmount);

        // User approves the manager for the `collateralAmount`.
        vm.prank(user1); // Prank user1 for this approval
        usdc.approve(address(manager), collateralAmount);

        // Expect the ERC20InsufficientBalance error from the MockERC20 contract.
        // The arguments are: `sender`, `balance`, `needed`.
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector,
                user1, // sender
                user1ActualBalance, // balance (what user1 actually has)
                collateralAmount // needed (the amount requested by mintSPY)
            )
        );

        // Attempt the mint operation. This should now revert with ERC20InsufficientBalance.
        vm.prank(user1); // Impersonate `user1` for the `mintSPY` call.
        manager.mintSPY(collateralAmount);
    }

    /**
     * @dev Tests that `mintSPY` reverts with `EnforcedPause` when the contract is paused.
     */
    function testMintSPY_RevertsWhenPaused() public {
        vm.prank(admin); // Impersonate `admin` to pause the contract.
        manager.pause();

        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        vm.prank(user1); // Impersonate `user1`.
        usdc.approve(address(manager), collateralAmount);

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(user1); // Impersonate `user1` for the `mintSPY` call.
        manager.mintSPY(collateralAmount);
    }

    /**
     * @dev Tests that `mintSPY` reverts with `OracleDataInvalid` if an underlying
     * price feed returns invalid data (e.g., a zero price for the collateral token),
     * preventing a valid collateralization calculation.
     */
    function testMintSPY_RevertsOnOracleDataInvalid() public {
        // Set collateral price (USDC) to 0 to trigger invalid calculation in manager.
        vm.prank(oracleAdmin); // Impersonate `oracleAdmin` to set mock price.
        usdcPriceFeed.setAnswer(0); // Set an invalid (zero) price.
        vm.stopPrank();

        uint256 collateralAmount = 100 * 10 ** USDC_DECIMALS;
        vm.prank(user1); // Impersonate `user1`.
        usdc.approve(address(manager), collateralAmount);

        // Expect `OracleDataInvalid` because the price is invalid (zero).
        vm.expectRevert(SyntheticAssetManager.OracleDataInvalid.selector);
        vm.prank(user1); // Impersonate `user1` for the `mintSPY` call.
        manager.mintSPY(collateralAmount);

        // Reset price feeds to normal for subsequent tests.
        vm.prank(oracleAdmin); // Impersonate `oracleAdmin`.
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        usdcPriceFeed.setAnswer(int256(USDC_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that `mintSPY` reverts with `InvalidCollateralRatio` if the
     * resulting collateralization ratio after minting would fall below the
     * `TARGET_COLLATERALIZATION_RATIO`. This test manipulates the target CR
     * to force this specific revert condition with normal values.
     */
    function testMintSPY_RevertsOnInvalidCollateralRatio() public {
        // 1. User `user1` mints a normal amount of sSPY to establish a position.
        // This will put their initial CR at `INITIAL_TARGET_CR` (150%).
        uint256 initialCollateralAmount = 1000 * 10 ** USDC_DECIMALS; // 1000 USDC
        vm.prank(user1);
        usdc.approve(address(manager), initialCollateralAmount);
        vm.prank(user1);
        manager.mintSPY(initialCollateralAmount);
        vm.stopPrank();

        // Capture initial debt and collateral for later calculation validation.
        uint256 user1InitialDebt = manager.userDebt(user1);
        uint256 user1InitialCollateral = manager.userCollateral(user1);

        // 2. The admin then increases the `TARGET_COLLATERALIZATION_RATIO` to a higher, but still normal, value.
        // This makes the existing position undercollateralized relative to the *new* target.
        uint256 newTargetCR = 25000; // 250% (a realistic, higher target)
        uint256 newMinCR = 20000; // 200% (must be less than newTargetCR)
        vm.prank(admin);
        manager.updateCollateralizationRatios(newTargetCR, newMinCR);
        vm.stopPrank();

        // Log the current ratio to observe its state relative to the new target.
        // This confirms the initial position is indeed undercollateralized relative to the new, higher target.
        uint256 currentRatioBeforeSecondMint = manager
            ._getCurrentCollateralRatio(user1);
        console.log(
            "Current CR after target CR increase (before second mint):",
            currentRatioBeforeSecondMint
        );
        assertTrue(
            currentRatioBeforeSecondMint < newTargetCR,
            "User's position should be undercollateralized relative to new target CR before second mint attempt"
        );

        // 3. `user1` attempts to mint *more* sSPY with a normal, small additional collateral.
        // Even with this addition, the overall cumulative position (initial + new) will still
        // fall short of the new, higher `TARGET_COLLATERALIZATION_RATIO`, triggering a revert.
        uint256 additionalCollateral = 100 * 10 ** USDC_DECIMALS; // 100 USDC (a normal additional amount)
        vm.prank(user1);
        usdc.approve(address(manager), additionalCollateral);

        // Predict the amount of sSPY that would be minted based on the *current* prices
        // and the `newTargetCR` (this internal calculation in `mintSPY` uses the new target CR).
        uint256 expectedSPYToMintOnSecondCall = manager.calculateMintAmount(
            additionalCollateral
        );

        // Predict the total user collateral and debt *after* this second mint attempt for the revert message.
        uint256 expectedTotalCollateral = user1InitialCollateral +
            additionalCollateral;
        uint256 expectedTotalDebt = user1InitialDebt +
            expectedSPYToMintOnSecondCall;

        // Predict the calculated ratio that will be passed to the revert error.
        // This `_calculateCollateralRatio` call uses the current (unmanipulated) SPY and collateral prices.
        uint256 expectedCalculatedRatioInRevert = manager
            ._calculateCollateralRatio(
                expectedTotalCollateral,
                expectedTotalDebt
            );

        // Log calculated values for debugging if it still fails.
        console.log(
            "Expected total collateral after second mint attempt:",
            expectedTotalCollateral
        );
        console.log(
            "Expected total debt after second mint attempt:",
            expectedTotalDebt
        );
        console.log(
            "Expected calculated ratio in revert (should be << newTargetCR):",
            expectedCalculatedRatioInRevert
        );
        console.log("New target CR for revert:", newTargetCR);

        // Expect the `InvalidCollateralRatio` revert with the calculated ratio and the new target CR.
        // The condition `expectedCalculatedRatioInRevert < newTargetCR` must be true for the test to pass.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                expectedCalculatedRatioInRevert, // currentRatio in error
                newTargetCR // requiredRatio in error (the new, higher target CR)
            )
        );

        // Attempt the second mint; this call should now revert as intended.
        vm.prank(user1);
        manager.mintSPY(additionalCollateral);

        // --- Cleanup after test ---
        // Reset collateralization ratios to their initial normal values for subsequent tests.
        vm.prank(admin);
        manager.updateCollateralizationRatios(
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR
        );
        vm.stopPrank();
    }

    // --- Test Suite: Redeeming Functionality (`redeemSPY`) ---

    /**
     * @dev Tests successful redemption of sSPY by a user.
     * Verifies:
     * - Correct burning of sSPY from the user.
     * - Correct transfer of collateral back to the user.
     * - Accurate updates to user's collateral and debt records.
     * - Correct total supply updates for sSPY.
     * - The `SPYRedeemed` event is emitted with precise values.
     * - The resulting collateralization ratio is healthy (at or above target).
     */
    function testRedeemSPY_Success() public {
        uint256 collateralAmount = 1000 * 10 ** USDC_DECIMALS; // Collateral for initial mint.

        // 1. User first mints sSPY to establish a position that can be redeemed.
        vm.startPrank(user1); // Start impersonating `user1`.
        usdc.approve(address(manager), collateralAmount);
        manager.mintSPY(collateralAmount);
        vm.stopPrank(); // Stop impersonating `user1`.

        // Get the actual total sSPY debt of the user after the initial mint.
        uint256 actualMintedSPY = manager.userDebt(user1);

        // Define the amount of sSPY the user wants to redeem (e.g., half of their current debt).
        uint256 sspyToRedeem = actualMintedSPY / 2;
        if (sspyToRedeem == 0) sspyToRedeem = 1; // Ensure a non-zero amount for redemption.

        // Calculate the expected collateral amount to be returned to the user.
        uint256 expectedCollateralReturn = calculateCollateralReturn(
            sspyToRedeem
        );

        // Predict the user's collateral and debt balances after the redemption.
        uint256 expectedUserCollateralAfterRedeem = manager.userCollateral(
            user1
        ) - expectedCollateralReturn;
        uint256 expectedUserDebtAfterRedeem = actualMintedSPY - sspyToRedeem;

        // User approves the manager to burn sSPY from their balance.
        vm.startPrank(user1); // Start impersonating `user1` for approval.
        sspy.approve(address(manager), actualMintedSPY); // Approve for the *full* current debt.
        vm.stopPrank(); // Stop impersonating `user1`.

        // Capture the sSPY total supply after initial minting but before redemption.
        uint256 initialSSPYSUPPLY_beforeRedeem = sspy.totalSupply();

        // Expect the `SPYRedeemed` event to be emitted with the predicted values.
        // The first boolean is true because `user` is an indexed parameter in the event.
        vm.expectEmit(true, false, false, false);
        emit SyntheticAssetManager.SPYRedeemed(
            user1, // user (indexed)
            sspyToRedeem, // sspyBurned
            expectedCollateralReturn // collateralReturned
        );

        // Perform the redemption operation as `user1`.
        vm.prank(user1); // Impersonate `user1` for the `redeemSPY` call.
        manager.redeemSPY(sspyToRedeem);

        // Assert final state and balances.
        // The initial USDC balance is from setUp(), plus any collateral returned, minus initial collateral deposit.
        assertApproxEqAbs(
            usdc.balanceOf(user1),
            INITIAL_USDC_MINT - collateralAmount + expectedCollateralReturn,
            1, // Small delta for potential integer division precision.
            "User1 USDC balance incorrect after redeem"
        );
        assertEq(
            sspy.balanceOf(user1),
            actualMintedSPY - sspyToRedeem,
            "User1 sSPY balance incorrect after redeem"
        );
        assertEq(
            sspy.totalSupply(),
            initialSSPYSUPPLY_beforeRedeem - sspyToRedeem,
            "sSPY total supply incorrect after redeem"
        );
        assertEq(
            manager.userDebt(user1),
            expectedUserDebtAfterRedeem,
            "User debt record incorrect after redeem"
        );
        assertApproxEqAbs(
            manager.userCollateral(user1),
            expectedUserCollateralAfterRedeem,
            1, // Small delta for potential integer division precision.
            "User collateral record incorrect after redeem"
        );

        // Verify that the user's collateralization ratio remains healthy after successful redemption.
        uint256 currentRatio = manager._getCurrentCollateralRatio(user1);
        assertTrue(
            currentRatio >= manager.TARGET_COLLATERALIZATION_RATIO(),
            "Collateral ratio should be at or above target after redeem"
        );
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `InvalidAmount` when a zero sSPY amount is provided for redemption.
     */
    function testRedeemSPY_RevertsOnZeroAmount() public {
        vm.prank(user1); // Impersonate `user1`.
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        manager.redeemSPY(0);
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `InsufficientFunds` if the user
     * attempts to redeem more sSPY than their current debt (sSPY balance held).
     * Uses the custom `InsufficientFunds` error from your contract.
     */
    function testRedeemSPY_RevertsOnInsufficientSPY() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        uint256 sspyToMint = manager.calculateMintAmount(collateralAmount);

        // User mints SPY to have a position.
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount); // User1 approves manager to spend USDC
        vm.prank(user1);
        manager.mintSPY(collateralAmount); // User1 calls mintSPY to get sSPY tokens

        // Attempt to redeem more sSPY than the user holds (sspyToMint + 1).
        uint256 sspyToRedeem = sspyToMint + 1; // More than user has

        // User approves manager to spend this (excessive) amount.
        // Even if they approve, the contract's internal balance check will fail.
        vm.prank(user1);
        sspy.approve(address(manager), sspyToRedeem);

        // Expect the custom `InsufficientFunds` error from your SyntheticAssetManager contract.
        // The arguments are: `owner`, `available`, `required`.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InsufficientFunds.selector,
                user1, // owner (the caller)
                manager.userDebt(user1), // available (their current debt/sSPY balance)
                sspyToRedeem // required (the amount they are trying to redeem)
            )
        );
        vm.prank(user1); // Ensure user1 is pranking for redeemSPY
        manager.redeemSPY(sspyToRedeem);
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `ERC20InsufficientAllowance` if the
     * `SyntheticAssetManager` contract does not have sufficient allowance to burn
     * the required sSPY tokens from the user's balance.
     * This error originates from the underlying ERC20 token's `transferFrom` function.
     */
    function testRedeemSPY_RevertsOnInsufficientAllowance() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        uint256 sspyToMint = manager.calculateMintAmount(collateralAmount);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);

        uint256 sspyToRedeem = sspyToMint;
        vm.prank(user1);
        // Approve less than required for redemption from user1 to the manager.
        sspy.approve(address(manager), sspyToRedeem - 1); // User approves less than needed.

        // Expect the ERC20InsufficientAllowance error from the MockERC20 contract.
        // The arguments are: `spender` (the address calling transferFrom, which is manager),
        // `allowance` (what was actually approved), and `needed` (what was requested).
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(manager), // The `spender` is the SyntheticAssetManager contract.
                sspyToRedeem - 1, // The allowance that was set (less than required).
                sspyToRedeem // The amount of sSPY the manager tried to transfer.
            )
        );
        // Attempt the redeem operation as user1; this should now revert.
        vm.prank(user1); // Ensure prank context is correct
        manager.redeemSPY(sspyToRedeem);
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `EnforcedPause` when the contract is paused.
     */
    function testRedeemSPY_RevertsWhenPaused() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        uint256 sspyToMint = manager.calculateMintAmount(collateralAmount);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);

        vm.prank(admin);
        manager.pause();

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(user1);
        manager.redeemSPY(sspyToMint / 2);
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `OracleDataInvalid` if a price feed
     * returns invalid data (e.g., a zero value), preventing accurate calculation of collateral return.
     */
    function testRedeemSPY_RevertsOnOracleDataInvalid() public {
        uint256 collateralAmount = 100 * 10 ** USDC_DECIMALS;

        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount); // User mints sSPY first.

        // Set SPY price to 0 to trigger the OracleDataInvalid error during redemption calculation.
        vm.prank(oracleAdmin); // Impersonate `oracleAdmin`.
        spyPriceFeed.setAnswer(0); // Set an invalid (zero) price.
        vm.stopPrank();

        uint256 sspyToRedeem = manager.userDebt(user1) / 2;
        if (sspyToRedeem == 0) sspyToRedeem = 1;

        vm.prank(user1); // Impersonate `user1`.
        sspy.approve(address(manager), sspyToRedeem);

        // Expect `OracleDataInvalid` because the price is invalid (zero).
        vm.expectRevert(SyntheticAssetManager.OracleDataInvalid.selector);
        vm.prank(user1); // Impersonate `user1` for the `redeemSPY` call.
        manager.redeemSPY(sspyToRedeem);

        // Reset price for subsequent tests.
        vm.prank(oracleAdmin); // Impersonate `oracleAdmin`.
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that `redeemSPY` reverts with `InvalidCollateralRatio` if the user's
     * position would become undercollateralized (CR falls below `MIN_COLLATERALIZATION_RATIO`)
     * after the attempted redemption. This test simulates a price fluctuation to achieve this state.
     */
    function testRedeemSPY_RevertsIfUnderCollateralized() public {
        // Define the collateral amount for the user's initial position.
        uint256 collateralAmount = 1000 * 10 ** USDC_DECIMALS; // 1000 USDC

        // 1. User mints SPY normally.
        // This sets their initial CR to INITIAL_TARGET_CR (15000).
        vm.startPrank(user1);
        usdc.approve(address(manager), collateralAmount); // User1 approves manager to spend USDC
        manager.mintSPY(collateralAmount); // User1 calls mintSPY
        vm.stopPrank();

        // 2. Simulate a significant SPY price increase to make the position undercollateralized.
        // We set SPY price to $7000. This makes the sSPY debt (which is fixed in sSPY units)
        // worth more in USD, thus lowering the collateralization ratio below the minimum.
        vm.prank(oracleAdmin); // Impersonate `oracleAdmin`.
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS))); // SPY price increases to $7000
        vm.stopPrank();

        // Log and assert that the user's position is indeed undercollateralized after the price change.
        uint256 currentCRAfterPriceChange = manager._getCurrentCollateralRatio(
            user1
        );
        uint256 minCR = manager.MIN_COLLATERALIZATION_RATIO();
        console.log(
            "Current CR after SPY price change (before redeem attempt):",
            currentCRAfterPriceChange
        );
        console.log("MIN_COLLATERALIZATION_RATIO:", minCR);
        assertTrue(
            currentCRAfterPriceChange < minCR,
            "Position should be undercollateralized before redeem attempt"
        );

        // 3. Define the amount of sSPY to redeem.
        // This is a small, non-zero amount intended to trigger the revert on an already unhealthy position.
        uint256 sspyToRedeem = 1 * (10 ** SSPY_DECIMALS); // Try redeeming 1 sSPY
        // Fallback if 1 sSPY is too large or 0 given current debt
        if (sspyToRedeem == 0 || sspyToRedeem > manager.userDebt(user1)) {
            sspyToRedeem = manager.userDebt(user1) / 100; // Fallback to 1% of debt
            if (sspyToRedeem == 0) sspyToRedeem = 1; // Ensure non-zero smallest amount
        }
        console.log("sSPY to redeem (actual amount):", sspyToRedeem);

        // 4. Calculate the expected collateral returned and the *resulting* collateral/debt.
        // This is necessary to predict the exact 'newRatio' that redeemSPY will calculate.
        uint256 expectedCollateralReturned = calculateCollateralReturn(
            sspyToRedeem
        );
        uint256 expectedRemainingDebt = manager.userDebt(user1) - sspyToRedeem;
        uint256 expectedRemainingCollateral = manager.userCollateral(user1) -
            expectedCollateralReturned;

        // 5. Calculate the *expected* new collateral ratio that `redeemSPY` would calculate
        // after the hypothetical redemption, using the current (manipulated) price feeds.
        uint256 expectedNewRatioInRevert = manager._calculateCollateralRatio(
            expectedRemainingCollateral,
            expectedRemainingDebt
        );

        // 6. User approves the manager to burn the sSPY from their balance.
        vm.prank(user1); // Prank user1 for this approval
        sspy.approve(address(manager), sspyToRedeem);

        // 7. Expect the `InvalidCollateralRatio` revert with the precisely calculated values.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.InvalidCollateralRatio.selector,
                expectedNewRatioInRevert, // currentRatio in error (the calculated ratio after redemption)
                manager.MIN_COLLATERALIZATION_RATIO() // requiredRatio in error (the minimum CR)
            )
        );
        // Attempt the redeem; this call should now revert as intended.
        vm.prank(user1); // Ensure `user1` is still the caller for `redeemSPY`.
        manager.redeemSPY(sspyToRedeem);

        // --- Cleanup after test ---
        // Reset SPY price to its normal value for consistency with other tests.
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    // --- Test Suite: Liquidation Functionality (`liquidate`) ---

    /**
     * @dev Tests successful liquidation of an undercollateralized position.
     * Verifies:
     * - Correct debt repayment by the liquidator.
     * - Correct collateral transfer (plus bonus) to the liquidator.
     * - Borrower's debt and collateral records are reduced.
     * - `PositionLiquidated` event is emitted.
     */
    function testLiquidate_FullPosition() public {
        uint256 collateralAmount = 10_000 * (10 ** USDC_DECIMALS);

        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);
        vm.stopPrank();

        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS))); // SPY increases significantly to make it very undercollateralized
        vm.stopPrank();

        // Check if user is actually undercollateralized before proceeding
        assertTrue(
            manager._getCurrentCollateralRatio(user1) <
                manager.MIN_COLLATERALIZATION_RATIO(),
            "User1 should be undercollateralized for full liquidation"
        );

        uint256 sspyToRepay = manager.userDebt(user1); // Liquidator repays ALL debt

        vm.startPrank(deployer);
        sspy.mint(liquidator, sspyToRepay); // Deployer has MINTER_ROLE on sspy (in mock scenario)
        vm.stopPrank();

        vm.prank(liquidator); // Liquidator approves manager
        sspy.approve(address(manager), sspyToRepay);
        vm.stopPrank();

        // Replicate calculation for expected collateral seized, including the bonus.
        // This calculation must precisely match the contract's internal logic.
        uint256 currentSpyPrice = manager._getSPYPriceRaw();
        uint256 currentUsdcPrice = manager._getCollateralPriceRaw();

        uint256 expectedCollateralSeized = (sspyToRepay *
            currentSpyPrice *
            (10 ** manager.collateralDecimals()) *
            (10000 + manager.LIQUIDATION_BONUS_RATIO())) /
            ((10 ** manager.sspyDecimals()) * currentUsdcPrice * 10000);

        // Expect the `PositionLiquidated` event.
        // The first boolean is true because `borrower` is an indexed parameter in the event.
        vm.expectEmit(true, false, false, false);
        emit SyntheticAssetManager.PositionLiquidated(
            user1, // borrower (indexed)
            liquidator, // liquidator
            sspyToRepay, // sspyRepaid
            expectedCollateralSeized, // collateralReceived
            manager.LIQUIDATION_BONUS_RATIO() // liquidationBonus
        );

        // Perform the liquidation.
        vm.prank(liquidator); // Impersonate `liquidator` for the `liquidate` call.
        manager.liquidate(user1, sspyToRepay);

        // Assert final balances and state.
        assertApproxEqAbs(
            usdc.balanceOf(liquidator),
            INITIAL_USDC_MINT + expectedCollateralSeized,
            1, // Small delta for potential integer division precision.
            "Liquidator USDC balance incorrect after full liquidation"
        );
        assertEq(
            manager.userDebt(user1),
            0,
            "Borrower debt should be zero after full liquidation"
        );
        // Note: The borrower's collateral will be reduced by the seized amount.
        // You might want to assert `manager.userCollateral(user1)` is `initialCollateral - expectedCollateralSeized`.
        // However, if the liquidation covers ALL debt, the collateral might also go to 0 or close to it.
        // The core check is the debt reduction and liquidator's gain.

        // Reset SPY price to normal for subsequent tests.
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that `liquidate` reverts with `InvalidZeroAddress`
     * when `borrower` address is `address(0)`.
     */
    function testLiquidate_RevertsOnBorrowerZeroAddress() public {
        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        vm.prank(liquidator);
        manager.liquidate(address(0), 1);
    }

    /**
     * @dev Tests that `liquidate` reverts with `InvalidAmount`
     * when the `sspyAmount` to repay is zero.
     */
    function testLiquidate_RevertsOnZeroAmount() public {
        vm.expectRevert(SyntheticAssetManager.InvalidAmount.selector);
        vm.prank(liquidator);
        manager.liquidate(user1, 0);
    }

    /**
     * @dev Tests that `liquidate` reverts with `LiquidationNotAllowed("Cannot self-liquidate")`
     * when a user attempts to liquidate their own position.
     */
    function testLiquidate_RevertsOnSelfLiquidation() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);
        vm.stopPrank();

        // Make position undercollateralized
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS)));
        vm.stopPrank();

        uint256 sspyToRepay = manager.userDebt(user1) / 2;

        // Expect the `LiquidationNotAllowed` error with the specific message.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.LiquidationNotAllowed.selector,
                "Cannot self-liquidate"
            )
        );
        vm.prank(user1); // User tries to liquidate themselves
        manager.liquidate(user1, sspyToRepay);

        // Reset SPY price for other tests
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that `liquidate` reverts with `LiquidationNotAllowed("Borrower has no debt")`
     * when attempting to liquidate a borrower who has no outstanding debt.
     */
    function testLiquidate_RevertsOnNoDebt() public {
        // user2 has no debt by default at the start of the test.
        // Expect the `LiquidationNotAllowed` error with the specific "Borrower has no debt" message.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.LiquidationNotAllowed.selector,
                "Borrower has no debt"
            )
        );
        vm.prank(liquidator);
        manager.liquidate(user2, 1); // Attempt to liquidate user2 with a small amount
    }

    /**
     * @dev Tests that `liquidate` reverts with `LiquidationNotAllowed("Position not undercollateralized")`
     * if the borrower's position is healthy (not undercollateralized).
     */
    function testLiquidate_RevertsWhenNotUndercollateralized() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);
        // The position is healthy after minting, so it should not be liquidatable.

        // SPY price remains normal, so the position is not undercollateralized.
        assertFalse(
            manager._isUndercollateralized(user1), // Use _isUndercollateralized for clarity
            "User1 should not be undercollateralized"
        );

        uint256 sspyToRepay = 100 * (10 ** SSPY_DECIMALS); // Arbitrary amount for attempt

        // Expect the `LiquidationNotAllowed` error with the specific "Position not undercollateralized" message.
        vm.expectRevert(
            abi.encodeWithSelector(
                SyntheticAssetManager.LiquidationNotAllowed.selector,
                "Position not undercollateralized"
            )
        );
        vm.prank(liquidator); // Liquidator attempts to liquidate
        manager.liquidate(user1, sspyToRepay);
    }

    /**
     * @dev Tests that `liquidate` reverts with `LiquidationAmountTooLarge`
     * if the `sspyAmount` to repay is greater than the borrower's outstanding debt.
     */
    function testLiquidate_RevertsOnLiquidationAmountTooLarge() public {
        uint256 collateralAmount = 10_000 * (10 ** USDC_DECIMALS);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);
        vm.stopPrank();

        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS))); // Make position undercollateralized
        vm.stopPrank();

        uint256 sspyToRepay = manager.userDebt(user1) + 1; // More than borrower has

        vm.expectRevert(
            SyntheticAssetManager.LiquidationAmountTooLarge.selector
        );
        vm.prank(liquidator);
        manager.liquidate(user1, sspyToRepay);

        // Reset SPY price for other tests
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that `liquidate` reverts with `EnforcedPause` when the contract is paused.
     */
    function testLiquidate_RevertsWhenPaused() public {
        uint256 collateralAmount = 1000 * (10 ** USDC_DECIMALS);
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);

        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS))); // Make position undercollateralized
        vm.stopPrank();

        uint256 sspyToRepay = manager.userDebt(user1) / 4;
        vm.startPrank(deployer);
        sspy.mint(liquidator, sspyToRepay);
        vm.stopPrank();

        vm.prank(liquidator);
        sspy.approve(address(manager), sspyToRepay);
        vm.stopPrank();

        vm.prank(admin);
        manager.pause();

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(liquidator);
        manager.liquidate(user1, sspyToRepay);

        // Reset SPY price for other tests
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    // --- Test Suite: Price Feed Related Functionality (`_getSPYPriceRaw`, `_getCollateralPriceRaw`) ---
    // These tests ensure the internal price fetching logic correctly handles errors from price feeds.

    /**
     * @dev Tests that accessing `_getSPYPriceRaw` (implicitly via `calculateMintAmount`)
     * reverts with `InvalidZeroAddress` if the sSPY price feed's address is `address(0)`
     * during contract construction.
     */
    function testGetSPYPrice_RevertsOnPriceFeedNotSet() public {
        // Temporarily redeploy manager with zero SPY price feed to isolate this test.
        vm.startPrank(deployer);
        // This constructor call itself will revert with InvalidZeroAddress, which is expected.
        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(0), // Zero address for SPY price feed
            address(usdcPriceFeed),
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests that `_getSPYPriceRaw` (implicitly via `calculateMintAmount`)
     * reverts with `OracleDataInvalid` if the SPY price feed returns invalid data (e.g., -1 or 0).
     */
    function testGetSPYPrice_RevertsOnOracleDataInvalid() public {
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(-1); // Invalid price
        vm.stopPrank();

        vm.expectRevert(SyntheticAssetManager.OracleDataInvalid.selector);
        manager.calculateMintAmount(1);

        // Reset
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests that accessing `_getCollateralPriceRaw` (implicitly via `calculateMintAmount`)
     * reverts with `InvalidZeroAddress` if the collateral price feed's address is `address(0)`
     * during contract construction.
     */
    function testGetCollateralPrice_RevertsOnPriceFeedNotSet() public {
        // Temporarily redeploy manager with zero collateral price feed to isolate this test.
        vm.startPrank(deployer);
        // This constructor call itself will revert with InvalidZeroAddress, which is expected.
        vm.expectRevert(SyntheticAssetManager.InvalidZeroAddress.selector);
        new SyntheticAssetManager(
            address(sspy),
            address(usdc),
            address(spyPriceFeed),
            address(0), // Zero address for collateral price feed
            INITIAL_TARGET_CR,
            INITIAL_MIN_CR,
            INITIAL_LIQUIDATION_BONUS
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests that `_getCollateralPriceRaw` (implicitly via `calculateMintAmount`)
     * reverts with `OracleDataInvalid` if the collateral price feed returns invalid data (e.g., -1 or 0).
     */
    function testGetCollateralPrice_RevertsOnOracleDataInvalid() public {
        vm.prank(oracleAdmin);
        usdcPriceFeed.setAnswer(-1); // Invalid price
        vm.stopPrank();

        vm.expectRevert(SyntheticAssetManager.OracleDataInvalid.selector);
        manager.calculateMintAmount(1);

        // Reset
        vm.prank(oracleAdmin);
        usdcPriceFeed.setAnswer(int256(USDC_PRICE_NORMAL));
        vm.stopPrank();
    }

    // --- Test Suite: Helper Functions (`calculateMintAmount`, `_calculateCollateralRatio`, `_isUndercollateralized`) ---

    /**
     * @dev Tests the accuracy of `calculateMintAmount` function.
     * Verifies that the calculated sSPY mint amount for a given collateral
     * is within an acceptable margin of error due to integer arithmetic.
     */
    function testCalculateMintAmount_Accuracy() public view {
        uint256 usdcAmount = 1000 * (10 ** USDC_DECIMALS); // 1000 USDC
        // Expected sSPY calculation:
        // (1000 USDC * $1/USDC) / ($5200/sSPY * 1.5 CR) = 1000 / (5200 * 1.5) = 1000 / 7800 = 0.1282051282 sSPY (approx).
        // Adjusted for sSPY decimals (18): 0.128205128205128205 * 10^18.
        uint256 expectedSspy = 128205128205128205;

        uint256 calculatedSspy = manager.calculateMintAmount(usdcAmount);
        assertApproxEqAbs(
            calculatedSspy,
            expectedSspy,
            1, // Allow a small margin of error due to integer division
            "Calculated mint amount is inaccurate"
        );
    }

    /**
     * @dev Tests the accuracy of the internal `_calculateCollateralRatio` function.
     * Uses pre-determined collateral and debt amounts that should result in the
     * `INITIAL_TARGET_CR` (150%). Verifies calculation precision.
     */
    function testCalculateCollateralRatio_Accuracy() public view {
        uint256 usdcAmount = 1000 * (10 ** USDC_DECIMALS); // 1000 USDC (collateral).
        uint256 sspyDebt = 128205128205128205; // Corresponds to 1000 USDC at 150% CR (debt).

        // The _calculateCollateralRatio function internally fetches prices, so no need to pass them.
        uint256 calculatedCR = manager._calculateCollateralRatio(
            usdcAmount,
            sspyDebt
        );

        console.log("Calculated CR in test:", calculatedCR); // Added for debugging
        console.log("Expected CR in test:", INITIAL_TARGET_CR); // Added for debugging

        assertApproxEqAbs(
            calculatedCR,
            INITIAL_TARGET_CR, // Should be around 15000 (150%)
            1, // Small delta for integer precision
            "Calculated collateral ratio is inaccurate"
        );
    }

    /**
     * @dev Tests `_calculateCollateralRatio` when user has zero debt.
     * Should result in a very high collateral ratio (effectively infinity, represented by type(uint256).max).
     */
    function testCalculateCollateralRatio_ZeroDebt() public view {
        uint256 collateral = 100 * 10 ** USDC_DECIMALS;
        uint256 debt = 0;
        uint256 calculatedCR = manager._calculateCollateralRatio(
            collateral,
            debt
        );
        // When debt is zero, CR should be effectively infinity (or a very large number).
        assertEq(
            calculatedCR,
            type(uint256).max,
            "CR should be max uint256 with zero debt"
        );
    }

    /**
     * @dev Tests `_calculateCollateralRatio` when user has zero collateral.
     * Should result in a zero collateral ratio (effectively zero).
     */
    function testCalculateCollateralRatio_ZeroCollateral() public view {
        uint256 collateral = 0;
        uint256 debt = 1 * 10 ** SSPY_DECIMALS;
        uint256 calculatedCR = manager._calculateCollateralRatio(
            collateral,
            debt
        );
        assertEq(calculatedCR, 0, "CR should be zero with zero collateral");
    }

    /**
     * @dev Tests the `_isUndercollateralized` function for a healthy position.
     */
    function testIsUndercollateralized_Healthy() public {
        uint256 collateralAmount = 1000 * 10 ** USDC_DECIMALS;
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);

        // Position is healthy (at TARGET_CR)
        assertFalse(
            manager._isUndercollateralized(user1),
            "Healthy position should not be undercollateralized"
        );
    }

    /**
     * @dev Tests the `_isUndercollateralized` function for an undercollateralized position.
     */
    function testIsUndercollateralized_Undercollateralized() public {
        uint256 collateralAmount = 1000 * 10 ** USDC_DECIMALS;
        vm.prank(user1);
        usdc.approve(address(manager), collateralAmount);
        vm.prank(user1);
        manager.mintSPY(collateralAmount);

        // Simulate price drop of collateral or rise of sSPY to make it undercollateralized
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(7000 * (10 ** CHAINLINK_PRICE_DECIMALS))); // Make sSPY more expensive, reducing CR
        vm.stopPrank();

        assertTrue(
            manager._isUndercollateralized(user1),
            "Position should be undercollateralized after price change"
        );

        // Reset SPY price for other tests
        vm.prank(oracleAdmin);
        spyPriceFeed.setAnswer(int256(SPY_PRICE_NORMAL));
        vm.stopPrank();
    }

    /**
     * @dev Tests the `_isUndercollateralized` function for a user with zero debt.
     * Such a user should never be considered undercollateralized.
     */
    function testIsUndercollateralized_ZeroDebt() public view {
        // user2 has no debt initially
        assertFalse(
            manager._isUndercollateralized(user2),
            "User with zero debt should not be undercollateralized"
        );
    }
}
