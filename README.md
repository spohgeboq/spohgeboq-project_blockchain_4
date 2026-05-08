# On-Chain Governance DAO System

A production-ready decentralized governance system built with Solidity, Foundry, and OpenZeppelin. This project implements a full DAO lifecycle including token-weighted voting, timelock execution, treasury management, and a minimal frontend interface.

## 🚀 Overview

This repository contains the complete implementation of a DAO:
1. **Governance Token**: ERC-20 with voting snapshots and permit functionality.
2. **Governor Contract**: Custom governance logic with configurable quorum and thresholds.
3. **Timelock**: A security layer that enforces a delay before executed proposals take effect.
4. **Treasury**: A contract controlled solely by the DAO to manage funds.
5. **Vesting**: Linear token release for team/founders.
6. **Frontend**: A minimal dApp to interact with the governance system.

## 🌐 Deployed Version

The live deployed version is available at: [https://blockchain.chiclab.me/](https://blockchain.chiclab.me/)

## 🛠 Tech Stack

- **Smart Contracts**: Solidity 0.8.24
- **Framework**: [Foundry](https://book.getfoundry.sh/)
- **Libraries**: [OpenZeppelin Contracts](https://openzeppelin.com/contracts/)
- **Frontend**: Vanilla JS + Ethers.js
- **Audit**: Slither Static Analysis

## 📂 Project Structure

```text
├── src/                # Smart Contract source code
│   ├── GovernanceToken.sol
│   ├── MyGovernor.sol
│   ├── Timelock.sol
│   ├── Treasury.sol
│   ├── TokenVesting.sol
│   └── Box.sol         # Demo contract for governance control
├── script/             # Deployment and interaction scripts
├── test/               # Comprehensive test suite
├── docs/               # Research, security, and deployment documentation
└── frontend/           # Minimal web interface
```

## 📜 Documentation

Detailed reports and checklists are available in the `docs/` directory:
- [Research Report](docs/research-report.md): Analysis of governance models and attacks.
- [Security Audit](docs/security-audit.md): Slither report and mitigation strategies.
- [Deployment Checklist](docs/deployment-checklist.md): Step-by-step production guide.
- [Monitoring Plan](docs/monitoring-plan.md): Event tracking and alert setup.

## 🔧 Getting Started

### Prerequisites
- Install [Foundry](https://getfoundry.sh/)

### Installation
```bash
# Clone the repository
git clone <your-repo-url>
cd assignment_4_BCH

# Install dependencies
forge install
```

### Build & Test
```bash
# Compile contracts
forge build

# Run all tests
forge test -vv
```

### Deployment (Local)
1. Start a local node:
   ```bash
   anvil
   ```
2. Run the deployment script:
   ```bash
   forge script script/DeployDAO.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
   ```

## 🔒 Security Features

- **Flash-Loan Resistance**: All voting power is calculated based on historical snapshots (`ERC20Votes`).
- **Delayed Execution**: The `TimelockController` ensures that users have time to react to passed proposals before they are executed.
- **Role-Based Access Control**: Strict administrative roles are assigned to the Governor contract, ensuring no single entity can override the community.

## 📄 License
This project is licensed under the MIT License.
