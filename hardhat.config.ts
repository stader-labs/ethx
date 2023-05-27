import 'dotenv/config'
import { ethers } from 'ethers'
import { HardhatUserConfig, task } from 'hardhat/config'
import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
import '@nomiclabs/hardhat-solhint'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-foundry'

const config: HardhatUserConfig = {
  // Your type-safe config goes here
  solidity: {
    compilers: [
      {
        version: '0.8.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: 'goerli',
  networks: {
    hardhat: {},
    goerli: {
      url: process.env.PROVIDER_URL ?? '',
      accounts: [process.env.OWNER_PRIVATE_KEY ?? ethers.Wallet.createRandom().privateKey],
    },
    zang: {
      url: process.env.PROVIDER_URL ?? '',
      accounts: [process.env.OWNER_PRIVATE_KEY ?? ethers.Wallet.createRandom().privateKey],
    },
    ethereum: {
      url: process.env.PROVIDER_URL ?? '',
      accounts: [process.env.OWNER_PRIVATE_KEY ?? ethers.Wallet.createRandom().privateKey],
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.API_KEY,
  },
}

export default config
