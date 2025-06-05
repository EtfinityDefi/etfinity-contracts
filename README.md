# Etfinity Smart Contracts 🔗

## Table of Contents

* [About](#about)
* [Core Features](#core-features)
* [Technologies Used](#technologies-used)
* [Getting Started](#getting-started)
    * [Prerequisites](#prerequisites)
    * [Installation](#installation)
    * [Compilation](#compilation)
    * [Testing](#testing)
    * [Deployment](#deployment)
* [Contract Overview](#contract-overview)
* [Contributing](#contributing)
* [License](#license)

---

## About

This repository contains the core Solidity smart contracts powering the Etfinity synthetic sSPY protocol. These on-chain components define the fundamental logic for sSPY minting, burning, collateral management, and other decentralized finance (DeFi) mechanisms. The contracts are designed with security, transparency, and extensibility in mind, built to operate on the **Ethereum** blockchain.

---

## Core Features

* **Synthetic sSPY Token:** ERC-20 compliant token representing synthetic exposure to the S&P 500.
* **Collateralized Debt Positions (CDPs):** Mechanisms for users to lock collateral (e.g., USDC, DAI) and mint sSPY.
* **Liquidation Logic:** Rules for maintaining the collateralization ratio and handling under-collateralized positions.
* **Oracle Integration:** (Simulated) Integration with external price feeds (e.g., Chainlink) for reliable S&P 500 price data.
* **Governance (Future):** Placeholder for future decentralized governance mechanisms for protocol upgrades and parameter changes.
* **Liquidity Provision:** Smart contracts facilitating liquidity pools for sSPY and collateral assets.

---

## Technologies Used

* **Solidity:** The programming language for writing smart contracts.
* **Foundry:** A blazing fast, portable, and modular toolkit for Ethereum application development written in Rust. It includes:
    * **Forge:** For compiling, testing, and deploying smart contracts.
    * **Anvil:** A local testnet node.
    * **Cast:** A command-line tool for interacting with EVM contracts and making RPC calls.
    * **Chisel:** A Solidity REPL.
* **OpenZeppelin Contracts:** Secure and community-audited smart contract libraries.

---

## Getting Started

Follow these steps to set up the development environment for the smart contracts using Foundry.

### Prerequisites

* **Git:** For cloning repositories.
* **A Unix-like environment:** macOS, Linux, or Windows Subsystem for Linux (WSL) on Windows. Foundry works best on these.
* **curl:** Usually pre-installed on Unix-like systems.

### Installation

1.  **Install Foundryup:** Open your terminal and run:
    ```bash
    curl -L [https://foundry.paradigm.xyz](https://foundry.paradigm.xyz) | bash
    ```
    Then, run `foundryup` to install the latest Foundry binaries:
    ```bash
    foundryup
    ```

2.  **Clone the repository:**
    ```bash
    git clone [https://github.com/EtfinityDefi/etfinity-contracts.git](https://github.com/EtfinityDefi/etfinity-contracts.git)
    cd etfinity-contracts
    ```

3.  **Initialize Foundry Project:** If the directory is empty, initialize it. If you cloned an existing Foundry repo, you can skip this.
    ```bash
    forge init --force # Use --force if the directory is not empty
    ```

4.  **Install OpenZeppelin Contracts:**
    ```bash
    forge install OpenZeppelin/openzeppelin-contracts
    ```

### Compilation

Compile your Solidity contracts using `forge`:

```bash
forge build
```

### Testing
Run the contract tests to ensure functionality and security using forge:

```bash
forge test
```

### Deployment
Deployment instructions will vary based on your target network. For local development with Anvil:

1. **Start Anvil (in a new terminal):**
```bash

anvil
```
2. **Create a .env file in your project root with a test private key (e.g., one provided by Anvil):**
PRIVATE_KEY=0x... # Your test private key
IMPORTANT: Add `.env` to your `.gitignore`!
3. **Deploy using a Solidity script: (Example: script/DeployEtfinity.s.sol)**

```bash
forge script script/DeployEtfinity.s.sol --rpc-url [http://127.0.0.1:8545](http://127.0.0.1:8545) --broadcast -vvvv
```
(Remember to fill in your actual deployment commands and details in your script.)

## Contract Overview
(Here, you would typically add a brief overview of your main contracts, their purpose, and how they interact. For example:)

* **`sSPYToken.sol`: The ERC-20 token contract for the synthetic S&amp;P 500 asset.**
* **`SyntheticAssetManager.sol`: Handles locking/unlocking collateral and minting/burning sSPY.**
* **`PriceOracle.sol`: (Or an interface to an external oracle) Provides price data for sSPY.**

## Contributing
Contributions are welcome! Feel free to open issues or submit pull requests for improvements, bug fixes, or new features.

## License
This project is licensed under the MIT License.
