import hre from "hardhat";
import upgrade from "./helpers/upgrade";
import proposeTransaction from "./helpers/proposeTransaction";

import addressJson from "./address.json";

const contractName = "ETHx";

const address: { [networkName: string]: { contracts: { name: string; address: string }[] } } = addressJson;

async function main() {
  const { ethers } = hre;

  const network = await ethers.provider.getNetwork();
  console.log(`Welcome, Proceeding with the actions.`);
  console.log(`You are upgrading on network ${network.name}:${Number(network.chainId)}`);

  try {
    console.log("Upgrading Contract...");
    const networkData = address[network.name];
    const contract = networkData.contracts.find((c) => c.name === contractName);
    if (contract === undefined) {
      throw new Error(`Contract ${contractName} not found`);
    }
    const {to, value, data} = await upgrade(contract?.address, contractName);
    await proposeTransaction(to, data, value);
  } catch (error) {
    console.error("An error occurred:", error);
  }
}

main();
