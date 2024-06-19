import "dotenv/config";
import { ethers } from "ethers";
import { HardhatUserConfig } from "hardhat/config";
import "@typechain/hardhat";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomiclabs/hardhat-solhint";
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
  // Your type-safe config goes here
  solidity: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: "mainnet",
  networks: {
    hardhat: {},
    goerli: {
      url: process.env.PROVIDER_URL_TESTNET ?? "",
      accounts: [process.env.OWNER_PRIVATE_KEY_TESTNET ?? ethers.Wallet.createRandom().privateKey],
    },
    mainnet: {
      url: process.env.PROVIDER_URL_MAINNET ?? "",
      accounts: [process.env.OWNER_PRIVATE_KEY_MAINNET ?? ethers.Wallet.createRandom().privateKey],
    },
    arbitrum: {
      url: process.env.PROVIDER_URL_ARBITRUM ?? "https://arb1.arbitrum.io/rpc",
      accounts: [process.env.OWNER_PRIVATE_KEY_ARBITRUM ?? ethers.Wallet.createRandom().privateKey],
    },
    holesky: {
      url: process.env.PROVIDER_URL_HOLESKY ?? "https://1rpc.io/holesky",
      accounts: [process.env.OWNER_PRIVATE_KEY_HOLESKY ?? ethers.Wallet.createRandom().privateKey],
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.API_KEY,
  },
};

export default config;
