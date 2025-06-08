// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../contracts/sSPYToken.sol"; // Import sSPYToken contract directly
import "./interfaces/IERC20WithDecimals.sol"; // Import IERC20WithDecimals from interfaces
import "./interfaces/IChainlinkAggregator.sol"; // Import IChainlinkAggregator from interfaces

/**
 * @title SyntheticAssetManager
 * @dev Manages the minting, redeeming, and liquidation of sSPY synthetic assets.
 * Users deposit collateral (e.g., USDC) to mint sSPY, and burn sSPY to redeem collateral.
 * This contract enforces collateralization ratios and handles liquidations for under-collateralized positions.
 */
contract SyntheticAssetManager is AccessControl, ReentrancyGuard, Pausable {
    // --- State Variables ---
    // Addresses of the associated token contracts and Chainlink price feeds.
    sSPYToken public immutable _sSPYToken;
    IERC20WithDecimals public immutable collateralToken;
    IChainlinkAggregator public sSPYPriceFeed; // Chainlink Aggregator for S&P 500 price (e.g., SPY/USD)
    IChainlinkAggregator public collateralPriceFeed; // Chainlink Aggregator for collateral token price (e.g., USDC/USD)

    // Collateralization parameters, stored as basis points (e.g., 15000 = 150.00%).
    // These define the financial rules for positions within the protocol.
    uint256 public TARGET_COLLATERALIZATION_RATIO;
    uint256 public MIN_COLLATERALIZATION_RATIO;
    uint256 public LIQUIDATION_BONUS_RATIO; // Liquidation bonus, also as basis points (e.g., 500 = 5.00%)

    // User-specific debt and collateral balances.
    // `userCollateral`: Amount of collateral (e.g., USDC) deposited by a user, in the collateral token's native decimals.
    // `userDebt`: Amount of sSPY tokens minted by a user, in sSPYToken's native decimals (18 decimals).
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDebt;

    // Decimal information for tokens and price feeds. Stored upon contract deployment
    // to avoid repeated calls to external contracts or oracles for fixed decimal values.
    uint8 public sspyDecimals;
    uint8 public collateralDecimals;
    uint8 public spyPriceDecimals;
    uint8 public collateralPriceDecimals;

    // --- Role Definitions ---
    // Defines a specific role for managing oracle addresses, distinct from the default admin role.
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    // --- Custom Errors ---
    // Custom errors provide more gas-efficient and descriptive error handling than `require` statements.
    error InvalidZeroAddress(); // Thrown when an address parameter is `address(0)`.
    error InvalidAmount(); // Thrown when a numerical amount parameter is zero or otherwise invalid.
    error InvalidCollateralRatio(uint256 currentRatio, uint256 requiredRatio); // Thrown when a collateral ratio constraint is violated.
    error InsufficientAllowance(address owner, address spender, uint256 amount); // Thrown when `transferFrom` fails due to insufficient allowance.
    error InsufficientFunds(address owner, uint256 available, uint256 required); // Thrown when an account has insufficient balance for an operation.
    error OracleDataStale(); // Thrown if Chainlink oracle data is too old. (Defined but not used in provided snippets)
    error OracleDataInvalid(); // Thrown if Chainlink oracle returns invalid data (e.g., negative or zero price).
    error LiquidationNotAllowed(string reason); // Thrown when a liquidation cannot proceed due to specific conditions.
    error LiquidationAmountTooLarge(); // Thrown if a liquidator attempts to repay more debt than outstanding.
    error CollateralCalculationError(); // Thrown if an internal calculation results in an unexpected zero value.
    error PriceFeedNotSet(); // Thrown if a price feed address is not set when attempting to use it.

    // --- Events ---
    // Events are emitted to log significant actions on the blockchain, making contract activity transparent.
    event SPYMinted(
        address indexed user, // The user who minted sSPY (indexed for easier filtering)
        uint256 collateralAmount, // The amount of collateral deposited
        uint256 sspyMinted, // The amount of sSPY minted
        uint256 collateralRatio // The user's new collateralization ratio after minting
    );
    event SPYRedeemed(
        address indexed user, // The user who redeemed sSPY (indexed)
        uint256 sspyBurned, // The amount of sSPY burned
        uint256 collateralReturned // The amount of collateral returned to the user
    );
    event PositionLiquidated(
        address indexed borrower, // The address of the liquidated borrower (indexed)
        address liquidator, // The address of the liquidator
        uint256 sspyRepaid, // The amount of sSPY debt repaid by the liquidator
        uint256 collateralReceived, // The amount of collateral received by the liquidator
        uint256 liquidationBonus // The liquidation bonus applied (in basis points)
    );
    event CollateralizationRatioUpdated(
        uint256 oldTargetRatio, // Previous target CR
        uint256 newTargetRatio, // New target CR
        uint256 oldMinRatio, // Previous minimum CR
        uint256 newMinRatio // New minimum CR
    );
    event LiquidationBonusUpdated(uint256 oldBonus, uint256 newBonus); // Previous and new liquidation bonus
    event OracleAddressUpdated(
        address indexed oldSPYOracle, // Previous sSPY oracle address (indexed)
        address indexed newSPYOracle, // New sSPY oracle address (indexed)
        address oldCollateralOracle, // Previous collateral oracle address
        address newCollateralOracle // New collateral oracle address
    );

    /**
     * @dev Constructor for the SyntheticAssetManager contract.
     * Initializes token addresses, price feeds, and collateralization parameters.
     * Grants DEFAULT_ADMIN_ROLE and ORACLE_ADMIN_ROLE to the deployer.
     *
     * @param _sSPYTokenAddress Address of the deployed sSPY token contract.
     * @param _collateralToken Address of the accepted collateral token (e.g., USDC).
     * @param _sSPYPriceFeed Address of the Chainlink AggregatorV3 price feed for S&P 500.
     * @param _collateralPriceFeed Address of the Chainlink AggregatorV3 price feed for collateral (e.g., USDC/USD).
     * @param _targetCR The target collateralization ratio (e.g., 15000 for 150%).
     * @param _minCR The minimum collateralization ratio before liquidation (e.g., 13000 for 130%).
     * @param _liquidationBonus The liquidation bonus as basis points (e.g., 500 for 5%).
     */
    constructor(
        address _sSPYTokenAddress,
        address _collateralToken,
        address _sSPYPriceFeed,
        address _collateralPriceFeed,
        uint256 _targetCR,
        uint256 _minCR,
        uint256 _liquidationBonus
    ) {
        // --- Input Validation ---
        // Revert if any critical dependency address is a zero address.
        if (
            _sSPYTokenAddress == address(0) ||
            _collateralToken == address(0) ||
            _sSPYPriceFeed == address(0) ||
            _collateralPriceFeed == address(0)
        ) {
            revert InvalidZeroAddress();
        }
        // Revert if initial ratios or bonus are zero, as they are fundamental to contract operation.
        if (_targetCR == 0 || _minCR == 0 || _liquidationBonus == 0) {
            revert InvalidAmount();
        }
        // Revert if the minimum collateralization ratio is not strictly less than the target ratio.
        if (_minCR >= _targetCR) {
            revert InvalidCollateralRatio(_minCR, _targetCR);
        }

        // --- State Initialization ---
        // Assign immutable token and price feed contract instances.
        _sSPYToken = sSPYToken(_sSPYTokenAddress);
        collateralToken = IERC20WithDecimals(_collateralToken);
        sSPYPriceFeed = IChainlinkAggregator(_sSPYPriceFeed);
        collateralPriceFeed = IChainlinkAggregator(_collateralPriceFeed);

        // Fetch and store decimal places from the connected token and price feed contracts.
        // This optimizes gas by avoiding repeated external calls for static information.
        sspyDecimals = _sSPYToken.decimals();
        collateralDecimals = collateralToken.decimals();
        spyPriceDecimals = sSPYPriceFeed.decimals();
        collateralPriceDecimals = collateralPriceFeed.decimals();

        // Set the initial collateralization ratio parameters.
        TARGET_COLLATERALIZATION_RATIO = _targetCR;
        MIN_COLLATERALIZATION_RATIO = _minCR;
        LIQUIDATION_BONUS_RATIO = _liquidationBonus;

        // Grant the contract deployer the default admin role and the oracle admin role.
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ORACLE_ADMIN_ROLE, _msgSender());
    }

    // --- Admin Functions ---

    /**
     * @dev Updates the addresses of the Chainlink price feeds used by the contract.
     * This function can only be called by an account possessing the `ORACLE_ADMIN_ROLE`.
     * Emits an `OracleAddressUpdated` event.
     *
     * @param _newSPYPriceFeed The new address for the sSPY (S&P 500) price feed.
     * @param _newCollateralPriceFeed The new address for the collateral price feed.
     */
    function updatePriceFeeds(
        address _newSPYPriceFeed,
        address _newCollateralPriceFeed
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        // Revert if any new price feed address is a zero address.
        if (
            _newSPYPriceFeed == address(0) ||
            _newCollateralPriceFeed == address(0)
        ) {
            revert InvalidZeroAddress();
        }
        // Emit an event logging the change of oracle addresses.
        emit OracleAddressUpdated(
            address(sSPYPriceFeed),
            _newSPYPriceFeed,
            address(collateralPriceFeed),
            _newCollateralPriceFeed
        );
        // Update the state variables with the new price feed addresses.
        sSPYPriceFeed = IChainlinkAggregator(_newSPYPriceFeed);
        collateralPriceFeed = IChainlinkAggregator(_newCollateralPriceFeed);

        // Update the stored decimal places for the new price feeds.
        spyPriceDecimals = sSPYPriceFeed.decimals();
        collateralPriceDecimals = collateralPriceFeed.decimals();
    }

    /**
     * @dev Updates the target and minimum collateralization ratio parameters.
     * This function can only be called by an account possessing the `DEFAULT_ADMIN_ROLE`.
     * Emits a `CollateralizationRatioUpdated` event.
     *
     * @param _newTargetCR New target collateralization ratio (basis points).
     * @param _newMinCR New minimum collateralization ratio (basis points).
     */
    function updateCollateralizationRatios(
        uint256 _newTargetCR,
        uint256 _newMinCR
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Revert if any new ratio is zero.
        if (_newTargetCR == 0 || _newMinCR == 0) {
            revert InvalidAmount();
        }
        // Revert if the new minimum ratio is not strictly less than the new target ratio.
        if (_newMinCR >= _newTargetCR) {
            revert InvalidCollateralRatio(_newMinCR, _newTargetCR);
        }
        // Emit an event logging the change of collateralization ratios.
        emit CollateralizationRatioUpdated(
            TARGET_COLLATERALIZATION_RATIO,
            _newTargetCR,
            MIN_COLLATERALIZATION_RATIO,
            _newMinCR
        );
        // Update the state variables with the new ratios.
        TARGET_COLLATERALIZATION_RATIO = _newTargetCR;
        MIN_COLLATERALIZATION_RATIO = _newMinCR;
    }

    /**
     * @dev Updates the liquidation bonus ratio.
     * This function can only be called by an account possessing the `DEFAULT_ADMIN_ROLE`.
     * Emits a `LiquidationBonusUpdated` event.
     *
     * @param _newBonus New liquidation bonus as basis points.
     */
    function updateLiquidationBonus(
        uint256 _newBonus
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Revert if the new bonus amount is zero.
        if (_newBonus == 0) {
            revert InvalidAmount();
        }
        // Emit an event logging the change of the liquidation bonus.
        emit LiquidationBonusUpdated(LIQUIDATION_BONUS_RATIO, _newBonus);
        // Update the state variable with the new bonus.
        LIQUIDATION_BONUS_RATIO = _newBonus;
    }

    /**
     * @dev Pauses the contract. When paused, minting, redeeming, and liquidations are blocked.
     * This function can only be called by an account possessing the `DEFAULT_ADMIN_ROLE`.
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause(); // Inherited from OpenZeppelin's Pausable contract.
    }

    /**
     * @dev Unpauses the contract. Resumes all operations that were blocked by pausing.
     * This function can only be called by an account possessing the `DEFAULT_ADMIN_ROLE`.
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause(); // Inherited from OpenZeppelin's Pausable contract.
    }

    // --- Internal Price Fetching Helpers ---

    /**
     * @dev Fetches the latest S&P 500 price from the Chainlink oracle.
     * Internal helper function with error handling for stale/invalid data.
     * Returns the raw price as returned by Chainlink (e.g., 5200 * 10**8 for $5200).
     * @return The latest S&P 500 price (raw value from oracle).
     */
    function _getSPYPriceRaw() public view returns (uint256) {
        if (address(sSPYPriceFeed) == address(0)) revert PriceFeedNotSet();
        (
            ,
            // uint80 roundId (skipped)
            int256 price, // int256 answer (captured)
            ,
            // uint256 startedAt (skipped)
            uint256 updatedAt, // uint256 updatedAt (captured)

        ) = // uint80 answeredInRound (implicitly skipped by position)

            sSPYPriceFeed.latestRoundData();

        if (updatedAt == 0 || price <= 0) revert OracleDataInvalid();
        return uint256(price);
    }

    /**
     * @dev Fetches the latest collateral token price from the Chainlink oracle.
     * Internal helper function with error handling for stale/invalid data.
     * Returns the raw price as returned by Chainlink (e.g., 1 * 10**8 for $1).
     * @return The latest collateral token price (raw value from oracle).
     */
    function _getCollateralPriceRaw() public view returns (uint256) {
        if (address(collateralPriceFeed) == address(0))
            revert PriceFeedNotSet();
        (
            ,
            // uint80 roundId (skipped)
            int256 price, // int256 answer (captured)
            ,
            // uint256 startedAt (skipped)
            uint256 updatedAt, // uint256 updatedAt (captured)

        ) = // uint80 answeredInRound (implicitly skipped by position)

            collateralPriceFeed.latestRoundData();

        if (updatedAt == 0 || price <= 0) revert OracleDataInvalid();
        return uint256(price);
    }

    // --- Core Protocol Functions ---

    /**
     * @dev Mints sSPY tokens by depositing collateral.
     * Before minting, it calculates the amount of sSPY to be minted to meet the
     * TARGET_COLLATERALIZATION_RATIO. It then verifies that the user's
     * overall position (existing + new collateral/debt) will remain at or
     * above this target ratio.
     * @param _collateralAmount The amount of collateral to deposit.
     * @return The new collateralization ratio of the user's position after minting.
     */
    function mintSPY(
        uint256 _collateralAmount
    ) public whenNotPaused returns (uint256) {
        // Revert if the collateral amount provided is zero.
        if (_collateralAmount == 0) {
            revert InvalidAmount();
        }

        // Calculate the maximum amount of sSPY that can be minted for the given collateral
        // while maintaining the TARGET_COLLATERALIZATION_RATIO.
        uint256 sspyToMint = calculateMintAmount(_collateralAmount);

        // Revert if the calculated sSPY amount to mint is zero. This can happen if
        // price feeds are extremely low, or if the calculation itself results in zero
        // due to precision or small inputs.
        if (sspyToMint == 0) {
            revert CollateralCalculationError();
        }

        // Calculate the user's *projected* total collateral and debt *before*
        // performing the actual token transfers and state updates. This ensures
        // the collateral ratio check is based on the state *after* the proposed mint.
        // Using native arithmetic operators directly as Solidity 0.8.x provides built-in overflow/underflow checks.
        uint256 projectedTotalCollateral = userCollateral[msg.sender] +
            _collateralAmount;
        uint256 projectedTotalDebt = userDebt[msg.sender] + sspyToMint;

        // Check if the user's *overall* collateralization ratio after this minting operation
        // would fall below the TARGET_COLLATERALIZATION_RATIO.
        // This prevents users from self-liquidating or worsening their position below the target.
        uint256 newRatio = _calculateCollateralRatio(
            projectedTotalCollateral,
            projectedTotalDebt
        );

        // If the projected new ratio is less than the required target, revert the transaction.
        // This is a critical risk management check.
        if (newRatio < TARGET_COLLATERALIZATION_RATIO) {
            revert InvalidCollateralRatio(
                newRatio,
                TARGET_COLLATERALIZATION_RATIO
            );
        }

        // If all checks pass, proceed with the actual token transfers and state updates.
        // Transfer the collateral from the user to this contract.
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            _collateralAmount
        );
        // Mint the calculated amount of sSPY tokens to the user.
        // Note: The `_sSPYToken.mint` function assumes this contract has the necessary MINTER_ROLE.
        _sSPYToken.mint(msg.sender, sspyToMint);

        // Update the user's recorded collateral and debt balances to reflect the changes.
        userCollateral[msg.sender] = projectedTotalCollateral;
        userDebt[msg.sender] = projectedTotalDebt;

        // Emit an event to log the successful minting operation and the resulting ratio.
        emit SPYMinted(msg.sender, _collateralAmount, sspyToMint, newRatio);

        // Return the final collateralization ratio for convenience (e.g., for front-end display).
        return newRatio;
    }

    /**
     * @dev Allows a user to burn sSPY tokens to redeem their deposited collateral.
     * The amount of collateral returned is proportional to the `sspyAmount` burned and current prices.
     * This function includes checks to prevent the user's position from becoming undercollateralized
     * after redemption. Adheres to a non-reentrant guard and can only be called when not paused.
     *
     * @param sspyAmount The amount of sSPY tokens to burn (in sSPYToken's native 18 decimals).
     * @return collateralReturned The amount of collateral returned to the user.
     */
    function redeemSPY(
        uint256 sspyAmount
    ) external nonReentrant whenNotPaused returns (uint256 collateralReturned) {
        // Revert if the sSPY amount to burn is zero.
        if (sspyAmount == 0) revert InvalidAmount();
        // Revert if the user tries to burn more sSPY than their outstanding debt.
        if (sspyAmount > userDebt[_msgSender()])
            revert InsufficientFunds(
                _msgSender(),
                userDebt[_msgSender()],
                sspyAmount
            );

        // Fetch current prices from the Chainlink oracles.
        uint256 spyPrice = _getSPYPriceRaw();
        uint256 collateralPrice = _getCollateralPriceRaw();

        // --- Robust Calculation for collateralToReturn ---
        // Convert the sSPY amount to its USD value, using 18 decimal precision for intermediate calculations.
        uint256 sspyValueUSD = (sspyAmount * spyPrice * (10 ** 18)) /
            ((10 ** sspyDecimals) * (10 ** spyPriceDecimals));

        // Convert the collateral price to an 18-decimal USD base for consistent unit alignment.
        uint256 collateralPriceUSDValue = collateralPrice *
            (10 ** (18 - collateralPriceDecimals));

        // Convert the USD value back to the collateral token amount, scaled to its native decimals.
        collateralReturned =
            (sspyValueUSD * (10 ** collateralDecimals)) /
            collateralPriceUSDValue;
        // --- End Robust Calculation ---

        // Revert if the calculated collateral to return is zero, indicating a potential calculation error.
        if (collateralReturned == 0) revert CollateralCalculationError();

        // Calculate the user's remaining debt and collateral after this hypothetical redemption.
        uint256 remainingDebt = userDebt[_msgSender()] - sspyAmount;
        uint256 remainingCollateral = userCollateral[_msgSender()] -
            collateralReturned;

        // If the user still has outstanding debt after this redemption, check their new collateralization ratio.
        // This prevents users from self-liquidating or making their position unhealthy below MIN_COLLATERALIZATION_RATIO.
        if (remainingDebt > 0) {
            uint256 newRatio = _calculateCollateralRatio(
                remainingCollateral,
                remainingDebt
            );
            // Revert if the new ratio falls below the minimum allowed collateralization ratio.
            if (newRatio < MIN_COLLATERALIZATION_RATIO) {
                revert InvalidCollateralRatio(
                    newRatio,
                    MIN_COLLATERALIZATION_RATIO
                );
            }
        }

        // Burn the sSPY tokens from the caller's balance by transferring them to address(0).
        // This relies on the sSPYToken contract having a burn mechanism or `transferFrom` to address(0) acting as a burn.
        // It also assumes the `transferFrom` call has already been approved by the user.
        _sSPYToken.transferFrom(_msgSender(), address(0), sspyAmount);

        // Transfer the calculated `collateralReturned` amount of collateral back to the caller.
        bool successTransfer = collateralToken.transfer(
            _msgSender(),
            collateralReturned
        );

        // Revert with `InsufficientFunds` if the collateral transfer from this contract fails.
        // This usually means the contract itself doesn't hold enough collateral, which shouldn't happen under normal operation.
        if (!successTransfer)
            revert InsufficientFunds(
                address(this),
                collateralToken.balanceOf(address(this)),
                collateralReturned
            );

        // Update the user's (caller's) collateral and debt records.
        userCollateral[_msgSender()] = remainingCollateral;
        userDebt[_msgSender()] = remainingDebt;

        // Emit an event logging the successful sSPY redemption.
        emit SPYRedeemed(_msgSender(), sspyAmount, collateralReturned);
        return collateralReturned; // Return the amount of collateral sent back.
    }

    /**
     * @dev Allows anyone to liquidate an under-collateralized position.
     * The liquidator repays a portion of the borrower's sSPY debt and, in return, receives
     * an equivalent value of the borrower's collateral plus a predefined liquidation bonus.
     * This function adheres to a non-reentrant guard and can only be called when not paused.
     *
     * @param borrower The address of the under-collateralized user whose position is to be liquidated.
     * @param sspyToRepay The amount of sSPY debt the liquidator wishes to repay for the borrower
     * (in sSPYToken's native 18 decimals).
     */
    function liquidate(
        address borrower,
        uint256 sspyToRepay
    ) external nonReentrant whenNotPaused {
        // --- Input and State Validations ---
        // Revert if the borrower address is zero.
        if (borrower == address(0)) revert InvalidZeroAddress();
        // Revert if the amount of sSPY to repay is zero.
        if (sspyToRepay == 0) revert InvalidAmount();
        // Revert if a user attempts to liquidate their own position.
        if (borrower == _msgSender())
            revert LiquidationNotAllowed("Cannot self-liquidate");

        // Revert if the target borrower has no outstanding debt.
        if (userDebt[borrower] == 0)
            revert LiquidationNotAllowed("Borrower has no debt");

        // Revert if the borrower's position is not currently undercollateralized.
        if (!_isUndercollateralized(borrower))
            revert LiquidationNotAllowed("Position not undercollateralized");

        // Revert if the liquidator attempts to repay more debt than the borrower actually has.
        if (sspyToRepay > userDebt[borrower])
            revert LiquidationAmountTooLarge();

        // Fetch current prices from the Chainlink oracles.
        uint256 spyPrice = _getSPYPriceRaw();
        uint256 collateralPrice = _getCollateralPriceRaw();

        // --- Robust Calculation for finalCollateralSeized ---
        // Convert the `sspyToRepay` amount to its USD value, using 18 decimal precision.
        uint256 sspyValueUSDToRepay = (sspyToRepay * spyPrice * (10 ** 18)) /
            ((10 ** sspyDecimals) * (10 ** spyPriceDecimals));

        // Convert the collateral price to an 18-decimal USD base.
        uint256 collateralPriceUSDValue = collateralPrice *
            (10 ** (18 - collateralPriceDecimals));

        // Calculate the bonus amount in USD based on the `LIQUIDATION_BONUS_RATIO`.
        uint256 bonusAmountUSD = (sspyValueUSDToRepay *
            LIQUIDATION_BONUS_RATIO) / 10000;
        // Calculate the total value in USD that the liquidator should receive, including the bonus.
        uint256 totalValueToLiquidatorUSD = sspyValueUSDToRepay +
            bonusAmountUSD;

        // Convert the total USD value back to the final amount of collateral to be seized,
        // scaled to the collateral token's native decimals.
        uint256 finalCollateralSeized = (totalValueToLiquidatorUSD *
            (10 ** collateralDecimals)) / collateralPriceUSDValue;
        // --- End Robust Calculation ---

        // Revert if the calculated collateral to be seized is zero, indicating a potential calculation error.
        if (finalCollateralSeized == 0) revert CollateralCalculationError();

        // Revert if the borrower's available collateral is less than the amount that needs to be seized.
        if (finalCollateralSeized > userCollateral[borrower]) {
            revert LiquidationNotAllowed(
                "Borrower has insufficient collateral to cover liquidation"
            );
        }

        // --- Asset Transfers and State Updates ---
        // Liquidator transfers the `sspyToRepay` amount of sSPY tokens to this contract (to be burned).
        // This assumes the liquidator has approved this contract to spend their sSPY tokens.
        bool success = _sSPYToken.transferFrom(
            _msgSender(),
            address(this),
            sspyToRepay
        );
        // Revert with `InsufficientAllowance` if the `transferFrom` call fails.
        if (!success)
            revert InsufficientAllowance(
                _msgSender(),
                address(this),
                sspyToRepay
            );

        // Burn the sSPY debt from the borrower's position. This essentially removes the sSPY
        // repaid by the liquidator from circulation.
        _sSPYToken.burn(address(this), sspyToRepay);

        // Transfer the `finalCollateralSeized` amount of collateral from this contract to the liquidator.
        bool transferSuccess = collateralToken.transfer(
            _msgSender(),
            finalCollateralSeized
        );
        // Revert with `InsufficientFunds` if the collateral transfer from this contract fails.
        if (!transferSuccess)
            revert InsufficientFunds(
                address(this),
                collateralToken.balanceOf(address(this)),
                finalCollateralSeized
            );

        // Update the borrower's outstanding debt and remaining collateral balances.
        userDebt[borrower] = userDebt[borrower] - sspyToRepay;
        userCollateral[borrower] =
            userCollateral[borrower] -
            finalCollateralSeized;

        // Emit an event logging the successful liquidation.
        emit PositionLiquidated(
            borrower,
            _msgSender(),
            sspyToRepay,
            finalCollateralSeized,
            LIQUIDATION_BONUS_RATIO
        );
    }

    // --- View/Pure Functions ---

    /**
     * @dev Calculates the maximum amount of sSPY that can be minted for a given collateral amount
     * based on current oracle prices and the `TARGET_COLLATERALIZATION_RATIO`.
     * This is a view function and does not modify state.
     *
     * @param _collateralAmount The amount of collateral to be used for minting
     * (in `collateralToken`'s native decimals).
     * @return sspyAmount The calculated amount of sSPY that can be minted
     * (in sSPYToken's native 18 decimals).
     */
    function calculateMintAmount(
        uint256 _collateralAmount
    ) public view returns (uint256 sspyAmount) {
        // If no collateral is provided, no sSPY can be minted.
        if (_collateralAmount == 0) return 0;

        // Fetch current prices from the Chainlink oracles.
        uint256 spyPrice = _getSPYPriceRaw();
        uint256 collateralPrice = _getCollateralPriceRaw();

        // --- Robust Calculation for sspyAmount ---
        // Convert collateral amount to its USD value, using 18 decimal precision for intermediate calculations.
        uint256 collateralUSDValue = (_collateralAmount *
            collateralPrice *
            (10 ** 18)) /
            ((10 ** collateralDecimals) * (10 ** collateralPriceDecimals));

        // Calculate the target debt value in USD based on the `TARGET_COLLATERALIZATION_RATIO`.
        uint256 targetDebtValueUSD = (collateralUSDValue * 10000) /
            TARGET_COLLATERALIZATION_RATIO;

        // Convert SPY price to an 18-decimal USD base.
        uint256 spyPriceUSDValue = spyPrice * (10 ** (18 - spyPriceDecimals));

        // Calculate the final sSPY amount to mint, converting from USD value back to sSPY token's native decimals.
        sspyAmount =
            (targetDebtValueUSD * (10 ** sspyDecimals)) /
            spyPriceUSDValue;
        // --- End Robust Calculation ---

        // Revert if the calculated sSPY amount is zero, indicating a potential underflow or precision issue.
        if (sspyAmount == 0) revert CollateralCalculationError();

        return sspyAmount;
    }

    /**
     * @dev Calculates a user's current collateralization ratio based on their
     * `userCollateral` and `userDebt` state variables and current oracle prices.
     *
     * @param _user The address of the user.
     * @return The user's current collateralization ratio as basis points (e.g., 15000 for 150%).
     */
    function _getCurrentCollateralRatio(
        address _user
    ) public view returns (uint256) {
        uint256 currentCollateral = userCollateral[_user];
        uint256 currentDebt = userDebt[_user];

        // If a user has no debt, their collateralization ratio is effectively infinite.
        if (currentDebt == 0) return type(uint256).max;

        // Fetch current prices from the Chainlink oracles.
        uint256 spyPrice = _getSPYPriceRaw();
        uint256 collateralPrice = _getCollateralPriceRaw();

        // --- Robust Calculation for Collateral Ratio ---
        // Convert both collateral and debt amounts to a common USD value (18 decimals for precision).
        uint256 collateralUSDValue = (currentCollateral *
            collateralPrice *
            (10 ** 18)) /
            ((10 ** collateralDecimals) * (10 ** collateralPriceDecimals));

        uint256 debtUSDValue = (currentDebt * spyPrice * (10 ** 18)) /
            ((10 ** sspyDecimals) * (10 ** spyPriceDecimals));

        // The formula for collateralization ratio is: (Collateral Value in USD / Debt Value in USD) * 10000 (for basis points).
        // Avoid division by zero if the debt value is effectively zero after scaling.
        if (debtUSDValue == 0) return type(uint256).max;

        return (collateralUSDValue * 10000) / debtUSDValue;
        // --- End Robust Calculation ---
    }

    /**
     * @dev Internal helper to calculate collateralization ratio for specific, arbitrary amounts
     * of collateral and sSPY debt. This version is made `public view` for testing purposes
     * and directly uses current raw prices fetched from oracles.
     *
     * @param _collateralAmount Amount of collateral (in collateral token decimals).
     * @param _sspyDebt Amount of sSPY debt (in sSPY token decimals).
     * @return The calculated collateralization ratio as basis points.
     */
    function _calculateCollateralRatio(
        uint256 _collateralAmount,
        uint256 _sspyDebt
    ) public view returns (uint256) {
        // If sSPY debt is zero, the ratio is effectively infinite.
        if (_sspyDebt == 0) return type(uint256).max;

        // Fetch current prices from the Chainlink oracles.
        uint256 spyPrice = _getSPYPriceRaw();
        uint256 collateralPrice = _getCollateralPriceRaw();

        // --- Robust Calculation for Collateral Ratio (for specific amounts) ---
        // Convert collateral and debt to a common USD value (18 decimals for precision).
        uint256 collateralUSDValue = (_collateralAmount *
            collateralPrice *
            (10 ** 18)) /
            ((10 ** collateralDecimals) * (10 ** collateralPriceDecimals));

        uint256 debtUSDValue = (_sspyDebt * spyPrice * (10 ** 18)) /
            ((10 ** sspyDecimals) * (10 ** spyPriceDecimals));

        // Avoid division by zero if the debt value is effectively zero after scaling.
        if (debtUSDValue == 0) return type(uint256).max;

        return (collateralUSDValue * 10000) / debtUSDValue;
        // --- End Robust Calculation ---
    }

    /**
     * @dev Checks if a user's position is currently undercollateralized.
     * A position is undercollateralized if its current ratio is below the `MIN_COLLATERALIZATION_RATIO`.
     *
     * @param _user The address of the user.
     * @return True if the position is undercollateralized, false otherwise.
     */
    function _isUndercollateralized(address _user) public view returns (bool) {
        // A user with no debt cannot be undercollateralized.
        if (userDebt[_user] == 0) return false;

        // Calculate the user's current collateralization ratio.
        uint256 currentRatio = _getCurrentCollateralRatio(_user);
        // Return true if the current ratio is less than the minimum required ratio.
        return currentRatio < MIN_COLLATERALIZATION_RATIO;
    }
}
