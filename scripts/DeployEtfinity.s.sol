// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/sSPYToken.sol";
import "../contracts/SyntheticAssetManager.sol";

contract DeployEtfinity is Script {
    function run() public returns (address sSPYTokenAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Get private key from .env

        // Start broadcasting transactions from the account associated with PRIVATE_KEY
        vm.startBroadcast(deployerPrivateKey);

        // Deploy sSPYToken
        // For the initialMinter, you can use one of the Anvil default accounts for now,
        // or placeholder until CollateralVault is deployed.
        // Example: using vm.addr(1) for a test minter role
        address initialMinter = vm.addr(1); // Placeholder: Replace with CollateralVault address later
        sSPYToken sspy = new sSPYToken(initialMinter);
        sSPYTokenAddress = address(sspy);

        console.log("sSPYToken deployed to:", sSPYTokenAddress);

        // vm.stopBroadcast() is automatically called at the end of the script

        // Deploy other contracts like CollateralVault, linking them
        // Example:
        // CollateralVault collateralVault = new CollateralVault(sSPYTokenAddress);
        // console.log("CollateralVault deployed to:", address(collateralVault));

        // You would then grant the CollateralVault the MINTER_ROLE on sSPYToken:
        // sspy.grantRole(sspy.MINTER_ROLE(), address(collateralVault));
    }
}
