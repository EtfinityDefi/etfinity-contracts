// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";

// Custom errors for MockERC20
error ERC20InvalidSender(address sender);
error ERC20InvalidReceiver(address receiver);
error ERC20InsufficientAllowance(
    address spender,
    uint256 allowance,
    uint256 needed
);
error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

/**
 * @title MockERC20
 * @dev A simple, standalone mock ERC20 token for testing purposes.
 * It implements IERC20 and manages its own state, allowing direct control over behavior.
 */
contract MockERC20 is IERC20, Context {
    // Internal state variables for balances, allowances, and total supply
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        // Mint initial supply to the deployer for convenience in tests
        _mint(_msgSender(), 100_000_000 * (10 ** decimals_));
    }

    // --- IERC20 Implementation ---
    function name() public view returns (string memory) {
        return _name;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][_msgSender()];
        if (currentAllowance < amount)
            revert ERC20InsufficientAllowance(
                _msgSender(),
                currentAllowance,
                amount
            );
        _approve(from, _msgSender(), currentAllowance - amount); // Decrease allowance
        _transfer(from, to, amount);
        return true;
    }

    // --- Internal Logic (modified _transfer function) ---
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ERC20InvalidSender(address(0));

        // Allow transfer to address(0) ONLY if 'from' is not address(0).
        // This distinguishes valid burn operations from invalid attempts to "mint" to address(0).
        if (to == address(0)) {
            // This path is for burning
            if (_balances[from] < amount)
                revert ERC20InsufficientBalance(from, _balances[from], amount);

            unchecked {
                _balances[from] -= amount;
                _totalSupply -= amount; // Decrement total supply on burn
            }
            emit Transfer(from, address(0), amount); // Emit Transfer event for burn
            return; // Exit after handling the burn
        }

        // Standard transfer logic for non-zero 'to' addresses
        if (_balances[from] < amount)
            revert ERC20InsufficientBalance(from, _balances[from], amount);

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount); // Emit Transfer event for regular transfers
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount); // Emit Approval event
    }

    // --- Mock Specific Functions ---
    // `_mint` remains the same as it correctly increments _totalSupply.
    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // `_burn` is now redundant if all burning paths go through `_transfer(..., address(0), ...)`.
    // However, if you explicitly call `_burn` in other places, you might keep it.
    // For this context, it's safer to remove the duplicate logic or ensure it's not called directly.
    // Given the `_transfer` is now robust for burning, `_burn` can be simplified or removed.
    // For now, let's keep it but ensure it aligns if used.
    // A public `burn` function would ideally call `_transfer(from, address(0), amount)`.
    function _burn(address from, uint256 amount) internal {
        // This function can now simply call the _transfer logic for burning.
        // It's less common to have a separate _burn internal function if _transfer handles address(0).
        // For consistency and to avoid double-handling _totalSupply:
        _transfer(from, address(0), amount);
    }

    // Public mint function for tests (callable by anyone)
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Public burn function for tests (callable by anyone, for specific address)
    // This public function should now call the internal `_transfer` to `address(0)`
    function burn(address from, uint256 amount) public {
        _transfer(from, address(0), amount); // Now uses the updated _transfer logic
    }
}
