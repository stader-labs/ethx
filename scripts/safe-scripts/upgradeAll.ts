const { ethers } = require("hardhat");
import upgradeHelper from "./helpers/upgrade";
import networkAddresses from "./address.json";
import proposeTransaction from "./helpers/proposeTransaction";
import {getArtifact, getDeployedBytecode, forceImportDeployedProxies} from "./helpers/utils";

async function main(networks: { [networkName: string]: { contracts: { name: string; address: string }[] } }) {
  const provider = ethers.provider;
  const networkName = await hre.network.name;
  const networkContracts = networks[networkName].contracts;

  console.log(`Checking contracts on network "${networkName}":`);

  for (let { name, address } of networkContracts) {
    console.log(`  - Checking contract "${name}" at address ${address}`);

    const deployedBytecode = await getDeployedBytecode(address, provider);
    if (!deployedBytecode) {
      console.error(`     Failed to retrieve deployed bytecode for "${name}". Skipping.`);
      continue;
    }
    try {
      // Uncomment below line if network files are lost and need to be force import.
      // await forceImportDeployedProxies(address, name);
      const compiledBytecode = await getArtifact(name);

      if (deployedBytecode !== compiledBytecode) {
        console.warn(`     Contract "${name}" is out of date!`);
        console.log(`      Upgrading to latest version...`);
       const {to, value, data} =  await upgradeHelper(address, name);
        await proposeTransaction(to, data, value);
      } else {
        console.log(`      "${name}" is already up to date on network "${networkName}".`);
      }
    } catch (error) {
      console.error(`Error checking or upgrading "${name}" on network "${networkName}":`, error);
    }
  }
}

main(networkAddresses)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
