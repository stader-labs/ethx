const { ethers, upgrades } = require("hardhat");
import { artifacts } from "hardhat";

export async function getDeployedBytecode(address: string, provider: any) {
  const contractImpl = await upgrades.erc1967.getImplementationAddress(address);
  const response = await provider.getCode(contractImpl);
  return response;
}

export async function getArtifact(name: string) {
  const artifact = await artifacts.readArtifact(name);
  return artifact.deployedBytecode;
}

export async function forceImportDeployedProxies(contractAddress: string, contractName: string) {
  const contractArtifact = await ethers.getContractFactory(contractName);
  await upgrades.forceImport(contractAddress, contractArtifact, { kind: "transparent" });
}
