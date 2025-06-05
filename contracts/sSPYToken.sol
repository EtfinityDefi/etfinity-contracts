// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/**
 * @title sSPYToken
 * @dev ERC-20 token representing synthetic exposure to the S&P 500.
 * This contract implements standard ERC-20 functionalities,
 * controlled minting and burning capabilities via AccessControl,
 * and emergency pausing functionality.
 *
 * The `MINTER_ROLE` is specifically designated for the `CollateralVault`
 * contract, which will be responsible for creating and destroying sSPY
 * tokens based on user collateral operations.
 *
 * The `DEFAULT_ADMIN_ROLE` can manage roles (including MINTER_ROLE)
 * and pause/unpause the token.
 */
contract sSPYToken is ERC20Pausable, AccessControl {
    // Define a unique role identifier for addresses authorized to mint and burn sSPY tokens.
    // This role will typically be assigned to the CollateralVault contract.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Constructor for the sSPYToken contract.
     * @param initialMinter The address that will initially be granted the MINTER_ROLE.
     * In a typical deployment, this should be the address of the
     * CollateralVault contract that will manage minting and burning.
     * The deployer (msg.sender) automatically receives the DEFAULT_ADMIN_ROLE.
     */
    constructor(address initialMinter) ERC20("Synthetic S&P 500", "sSPY") {
        // Grant the contract deployer (the address that creates this contract)
        // the DEFAULT_ADMIN_ROLE. This address will then be able to manage other roles.
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // Grant the specified initialMinter address the MINTER_ROLE.
        // This address (e.g., the CollateralVault) will be the sole entity
        // authorized to call the `mint` and `burn` functions of this token.
        require(
            initialMinter != address(0),
            "sSPYToken: initial minter cannot be the zero address"
        );
        _grantRole(MINTER_ROLE, initialMinter);
    }

    /**
     * @dev Mints `amount` new sSPY tokens and assigns them to `to`.
     * This function can only be called by an address that has been granted the `MINTER_ROLE`.
     * It also respects the paused state of the contract (transfers are blocked when paused).
     * @param to The address that will receive the newly minted tokens.
     * @param amount The amount of sSPY tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        // The internal _mint function automatically handles checks like `to != address(0)`
        // and respects the paused state through _update.
        _mint(to, amount);
    }

    /**
     * @dev Burns `amount` sSPY tokens from `from`.
     * This function can only be called by an address that has been granted the `MINTER_ROLE`.
     * It also respects the paused state of the contract (transfers are blocked when paused).
     * @param from The address from which tokens will be burned.
     * @param amount The amount of sSPY tokens to burn.
     */
    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
        // The internal _burn function automatically handles checks like `from != address(0)`
        // and respects the paused state through _update.
        _burn(from, amount);
    }

    /**
     * @dev Pauses all token transfers (minting, burning, and standard ERC20 transfers).
     * This function can only be called by an address that has the `DEFAULT_ADMIN_ROLE`.
     * It serves as an emergency stop mechanism for critical situations.
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers, allowing them to resume.
     * This function can only be called by an address that has the `DEFAULT_ADMIN_ROLE`.
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Overrides the internal `_update` function from OpenZeppelin's ERC20.
     * This override is necessary to integrate the pausing functionality from `ERC20Pausable`.
     * Before any token transfer occurs, `_update` will check if the contract is paused.
     * If paused, it will revert the transaction.
     * @param from The sender address of the tokens.
     * @param to The receiver address of the tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Pausable) {
        // Call the parent's _update function which includes the `whenNotPaused` check.
        super._update(from, to, amount);
    }

    // --- Production Readiness Checklist (Further Considerations) ---
    // 1.  **Auditing:** This contract must undergo a thorough audit by reputable blockchain security firms before production deployment.
    // 2.  **Multi-signature Admin:** The `DEFAULT_ADMIN_ROLE` should ideally be controlled by a multi-signature wallet (e.g., Gnosis Safe)
    //     instead of a single External Owned Account (EOA) to prevent single points of failure and enhance security for critical operations.
    // 3.  **Timelock:** Critical admin actions (e.g., changing the `MINTER_ROLE`, pausing/unpausing) could be subject to a timelock contract.
    //     This would introduce a delay before actions take effect, giving users and monitoring systems time to react if an unauthorized or
    //     malicious action is initiated.
    // 4.  **Upgradability:** For this base token contract, immutability is often preferred for simplicity and trust. However, for more complex
    //     tokens or protocols, upgradability patterns (like UUPS proxies) might be considered. If upgradability is desired, additional
    //     OpenZeppelin contracts (`UUPSUpgradeable`) and careful design considerations are required. For sSPY, it's often the `CollateralVault`
    //     that is made upgradable, rather than the token itself.
    // 5.  **Event Monitoring:** Ensure off-chain systems are set up to monitor all relevant events emitted by this contract (e.g., `Transfer`,
    //     `Approval`, `RoleGranted`, `RoleRevoked`, `Paused`, `Unpaused`) for real-time tracking and analytics.
}
