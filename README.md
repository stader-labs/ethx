# ETHx

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

[![Test](https://github.com/stader-labs/ethx/actions/workflows/ci-image.yml/badge.svg)](https://github.com/stader-labs/ethx/actions/workflows/ci-image.yml)
[![codecov](https://codecov.io/gh/stader-labs/ethx/graph/badge.svg?token=PWU803B3QS)](https://codecov.io/gh/stader-labs/ethx)

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

## Contracts Deployed

### ETH Mainnet

STADER_CONFIG: 0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB

VAULT_FACTORY: 0x03ABEEC03BF39ac5A5C8886cF3496326d8164E1E

AUCTION: 0x85A22763f94D703d2ee39E9374616ae4C1612569

ETHx: 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b

OPERATOR_REWARDS_COLLECTOR: 0x84ffDC9De310144D889540A49052F6d1AdB2C335

PENALTY: 0x84645f1B80475992Df2C65c28bE6688d15dc6ED6

PERMISSIONED_NODE_REGISTRY: 0xaf42d795A6D279e9DCc19DC0eE1cE3ecd4ecf5dD

PERMISSIONED_POOL: 0x09134C643A6B95D342BdAf081Fa473338F066572

PERMISSIONLESS_NODE_REGISTRY: 0x4f4Bfa0861F62309934a5551E0B2541Ee82fdcF1

PERMISSIONLESS_POOL: 0xd1a72Bd052e0d65B7c26D3dd97A98B74AcbBb6c5

POOL_SELECTOR: 0x62e0b431990Ea128fe685E764FB04e7d604603B0

POOL_UTILS: 0xeDA89ed8F89D786D816F8E14CF8d2F90c6BF763f

SD_COLLATERAL: 0x7Af4730cc8EbAd1a050dcad5c03c33D2793EE91f

PERMISSIONED_SOCIALIZING_POOL: 0x9d4C3166c59412CEdBe7d901f5fDe41903a1d6Fc

PERMISSIONLESS_SOCIALIZING_POOL: 0x1DE458031bFbe5689deD5A8b9ed57e1E79EaB2A4

INSURANCE_FUND: 0xbe3781CE437Cc3fC8c8167913B4d462347D11F20

STADER_ORACLE: 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737

STADER_STAKE_POOL_MANAGER: 0xcf5EA1b38380f6aF39068375516Daf40Ed70D299

USER_WITHDRAWAL_MANAGER: 0x9F0491B32DBce587c50c4C43AB303b06478193A7

NODE_EL_REWARD_VAULT: 0x97c92752DD8a8947cE453d3e35D2cad5857367af

VALIDATOR_WITHDRAWAL_VAULT: 0x3073cC90aD39E0C30bb0d4c70F981FbD00f3458f

SD_UTILITY_POOL: 0xED6EE5049f643289ad52411E9aDeC698D04a9602

SD_INCENTIVE_CONTROLLER: 0xe225825bcf20F39E2F2e2170412a3247D83492D0

ETHx_ETH Feed Chainlink V3 Format: 0xdd487947c579af433AeeF038Bf1573FdBB68d2d3

### ETH Holesky

STADER_CONFIG=0x50FD3384783EE49011E7b57d7A3430a762b3f3F2

VAULT_FACTORY=0xc83B40Ad346e0dEFeF2cD9989a1bC6f6B86772bD

AUCTION=0xbADbFbda220806ab9ad59C6b9eDe3d6631B4Eb1d

ETHx=0xB4F5fc289a778B80392b86fa70A7111E5bE0F859

OPERATOR_REWARDS_COLLECTOR=0x3E018b4DD6105426Aa35593a111C37A6c7bf7D8e

PENALTY=0x330Bc84eae6dEC3282A94359cC0eb7856fa399c3

PERMISSIONED_NODE_REGISTRY=0x146B82b471dA1fC7f8E04DD33a6aD063f212F24B

PERMISSIONED_POOL=0x404D6534C0732B2B2E177B82DFd3526AB76f1f47

PERMISSIONLESS_NODE_REGISTRY=0x08CDa83AfEA67cC932daEb2Cacf1ee2C09Fb0F75

PERMISSIONLESS_POOL=0x9d8003bfd1AA879776e279BAa9E5C9C0a9B69E21

POOL_SELECTOR=0xC6047C19865EB6f6D51109cf9B0a33e9746395e3

POOL_UTILS=0x74D92F18017aDbA80052Ae1C66b29ee35d477644

SD_COLLATERAL=0x88D9599C5955DC40371d462D1b6F994B55316242

PERMISSIONED_SOCIALIZING_POOL=0xda68C8E02747C246250ca0D28c1bbb5949d90fBC

PERMISSIONLESS_SOCIALIZING_POOL=0x47C34e95a15C022450711174E1F0b676618cBa58

INSURANCE_FUND=0x6118558114A1d2c9634dA647C3D3330CADc8913C

STADER_ORACLE=0x90ED1c6563e99Ea284F7940b1b443CE0BC4fC3e4

STADER_STAKE_POOL_MANAGER=0x7F09ceb3874F5E35Cd2135F56fd4329b88c5d119

USER_WITHDRAWAL_MANAGER=0x3F6F1C1081744c18Bd67DD518F363B9d4c76E1d2

NODE_EL_REWARD_VAULT=0x69Ee750A6b2B7F0a3D00fe5782EE2951Adf0F1A7

VALIDATOR_WITHDRAWAL_VAULT=0xE511b7a58248DfCa0424d1B704403C932E4C0762

SD_UTILITY_POOL=0x854b60e64E7dedd328bf782Db5601fbc07132b66

SD_INCENTIVE_CONTROLLER=0x016524D32DA97621E51605AbAABc140aA039D29a

### Arbitrum

ETHx: 0xED65C5085a18Fa160Af0313E60dcc7905E944Dc7

### Optimism

ETHx: 0xc54B43eaF921A5194c7973A4d65E055E5a1453c2
