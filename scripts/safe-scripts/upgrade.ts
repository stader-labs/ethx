import hre from "hardhat";
import upgrade from "./helpers/upgrade";

import addressJson from "./address.json";

const contractName = "ETHx";

const address: any = addressJson;

async function main() {
  const { ethers } = hre;

  const network = await ethers.provider.getNetwork();
  console.log(`Welcome, Proceeding with the actions.`);
  console.log(`You are upgrading on network ${network.name}:${Number(network.chainId)}`);

  try {
    console.log("Upgrading Contract...");
    await upgrade(address[network.name][contractName], contractName);
  } catch (error) {
    console.error("An error occurred:", error);
  }
}

main();
