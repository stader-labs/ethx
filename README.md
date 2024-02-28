[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

# Overview

ETHx is a multi pool architecture for node operations, designed for decentralization, scalability, and resilience. This design is integral to our ability to democratize node operations and adapt to increasing demand.
Our structure includes a permissionless pool, where anyone can participate and operate nodes, thereby fostering widespread participation. Alongside this, we also feature a permissioned pool. This is a select group of validators known for their consistent high performance.

# Resources

- [ETHx Architecture](https://miro.com/app/board/uXjVMDv5XKo=/)
- [Contract Addresses](https://staderlabs.gitbook.io/ethereum/smart-contracts#ethx-mainnet-smart-contracts)
- [Onboarding Documentation](https://staderlabs.gitbook.io/ethereum/)

# Deploy

`NOTE`: Default Branch for repo is [mainnet_V0](https://github.com/stader-labs/ethx/tree/mainnet_V0)

```shell
npx hardhat compile
npx hardhat run scripts/deployContracts.ts
```

# Verify

```shell
npx hardhat compile
npx hardhat run scripts/verifyContracts.ts
```

# Tests

Installing foundry:

```bash
# install foundry
curl -L https://foundry.paradigm.xyz | bash

# extra step for macOS
brew install libusb

# run
foundryup
npm install
forge install
```

Using the test suite:

```bash
forge build
forge test
forge test --gas-report
forge coverage
```

# Integration

Check the Integration guide [here](https://github.com/stader-labs/ethx/blob/mainnet_V0/INTEGRATION.md)

# Dependencies
This project incorporates code from the following external sources:
- Compound Labs, Inc. (licensed under the BSD-3-Clause License)

- Ben Hauser (licensed under the MIT License)

The borrowed code contributes to 'SDUtilityPool.sol for computing fee, utilizer balance and exchange rate for a C-token based model' and 'SDIncentiveController.sol for computing incentivize rewards to the delegator of UtilityPool' respectively. For further details on the specific code sections and their respective licenses, please refer to the Third-Party Licenses file.

Link to Third-Party Licenses:

[THIRD-PARTY-LICENSES.md](https://github.com/stader-labs/ethx/blob/mainnet_V0/THIRD-PARTY-LICENSES.md)

