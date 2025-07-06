// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // For console.log in tests
import "../../contracts/sSPYToken.sol";
import "@openzeppelin/contracts/access/AccessControl.sol"; // Import AccessControl for its custom error
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol"; // Import ERC20Pausable for its custom error

contract sSPYTokenTest is Test {
    sSPYToken public sspy;
    address public deployer;
    address public minter;
    address public user1;
    address public user2;

    function setUp() public {
        // Set up test accounts
        deployer = makeAddr("deployer"); // Create a deterministic address for deployer
        minter = makeAddr("minter"); // Create a deterministic address for minter
        user1 = makeAddr("user1"); // Create a deterministic address for user1
        user2 = makeAddr("user2"); // Create a deterministic address for user2

        // Deal ETH to deployer and minter if they need to send transactions
        vm.deal(deployer, 10 ether);
        vm.deal(minter, 10 ether);

        // Deploy the sSPYToken contract, granting minter role to `minter` address
        vm.startPrank(deployer); // Deploy as the deployer
        sspy = new sSPYToken(minter);
        vm.stopPrank(); // Stop impersonating deployer
    }

    function testMintingByMinter() public {
        // Test that the minter can mint tokens
        uint256 amountToMint = 100 * 1e18; // 100 tokens (assuming 18 decimals)

        vm.startPrank(minter); // Act as the minter
        sspy.mint(user1, amountToMint);
        vm.stopPrank();

        assertEq(
            sspy.balanceOf(user1),
            amountToMint,
            "User1 should have minted sSPY"
        );
        assertEq(
            sspy.totalSupply(),
            amountToMint,
            "Total supply should reflect minted amount"
        );
    }

    function testCannotMintWithoutMinterRole() public {
        // Test that a non-minter cannot mint tokens
        uint256 amountToMint = 50 * 1e18;

        // Expect revert with the custom error AccessControlUnauthorizedAccount
        // It takes (address account, bytes32 role) as arguments
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                user2,
                sspy.MINTER_ROLE()
            )
        );
        vm.startPrank(user2); // Act as a regular user (not minter)
        sspy.mint(user2, amountToMint);
        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        // Test pause functionality
        vm.startPrank(deployer); // Only admin can pause
        sspy.pause();
        vm.stopPrank();

        assertTrue(sspy.paused(), "Contract should be paused");

        // Verify transfers are blocked when paused
        vm.startPrank(minter);
        // Expect revert with the custom error EnforcedPause()
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        sspy.mint(user1, 10 * 1e18);
        vm.stopPrank();

        // Test unpause functionality
        vm.startPrank(deployer);
        sspy.unpause();
        vm.stopPrank();

        assertFalse(sspy.paused(), "Contract should be unpaused");
    }
}
