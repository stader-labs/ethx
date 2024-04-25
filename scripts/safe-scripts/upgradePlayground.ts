import hardhat from "hardhat";
// import { ethers, upgrades } from "hardhat";

export class Upgrader {
  private async getArtifacts() {
    return {
      ETHx: await hardhat.ethers.getContractFactory("contracts/L2/ETHx.sol:ETHx"),
    };
  }

  // use to validate upgrade before running it or passing it to Gnosis Safe
  async validateUpgrade(contractName: string, contractAddress: string) {
    const artifacts = await this.getArtifacts();

    const contractArtifact = artifacts[contractName];

    if (contractArtifact === undefined) {
      throw new Error(`Contract ${contractName} not found`);
    }

    await hardhat.upgrades.validateUpgrade(contractAddress, contractArtifact, {
      kind: "transparent",
      unsafeAllow: ["delegatecall"],
    });
  }

  // used to store impl record for proxies in .openzeppelin folder
  async forceImportDeployedProxies(contractName: string, contractAddress: string) {
    const artifacts = await this.getArtifacts();

    console.log("artifacts");

    const contractArtifact = artifacts[contractName];

    if (contractArtifact === undefined) {
      throw new Error(`Contract ${contractName} not found`);
    }

    console.log("contractArtifact");

    await hardhat.upgrades.forceImport(contractAddress, contractArtifact, { kind: "transparent" });
  }

  async validateImplementation(contractName: string) {
    const artifacts = await this.getArtifacts();

    const contractArtifact = artifacts[contractName];

    if (contractArtifact === undefined) {
      throw new Error(`Contract ${contractName} not found`);
    }

    await hardhat.upgrades.validateImplementation(contractArtifact);
  }

  async run(contractName: string, contractAddress: string) {
    const artifacts = await this.getArtifacts();

    const contractArtifact = artifacts[contractName];

    if (contractArtifact === undefined) {
      throw new Error(`Contract ${contractName} not found`);
    }

    const contractInstance = await hardhat.upgrades.upgradeProxy(contractAddress, contractArtifact, {});
    await contractInstance.deployTransaction.wait();

    const proxyAdmin = await hardhat.upgrades.admin.getInstance();
    const contractImpl = await proxyAdmin.callStatic.getProxyImplementation(contractInstance.address);
    console.log("Contract implementation ", contractImpl);
  }
}

async function main() {
  console.log("START!");

  const upgrader = new Upgrader();
  // (contractName: string, contractAddress: string)
  await upgrader.validateUpgrade("ETHx", "0xED65C5085a18Fa160Af0313E60dcc7905E944Dc7");
  // await upgrader.forceImportDeployedProxies("ETHx", "0xED65C5085a18Fa160Af0313E60dcc7905E944Dc7");

  // await upgrader.validateImplementation("ETHx");
  // await upgrader.run("", "");

  console.log("END!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
