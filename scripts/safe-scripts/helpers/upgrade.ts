import hre from "hardhat";
async function main(contractAddress: string, contractName: string) {
  const { ethers, upgrades } = hre;
  const network = await ethers.provider.getNetwork();

  const proxyAdminContractAddress = await upgrades.erc1967.getAdminAddress(contractAddress);

  const contractFactory = await ethers.getContractFactory(contractName);

  await upgrades.validateUpgrade(contractAddress, contractFactory, {
    kind: "transparent",
    unsafeAllow: ["delegatecall"],
  });

  console.log(`Preparing upgrade for ${contractName} at ${contractAddress}`);
  const newImplementationAddress = await upgrades.prepareUpgrade(contractAddress, contractFactory, {
    redeployImplementation: "always",
    unsafeAllow: ["delegatecall"],
  });

  const proxyAdminContract = await ethers.getContractAt("ProxyAdmin", proxyAdminContractAddress);

  console.log(`Proposing upgrade for ${contractName} at ${contractAddress}`);
  const encodedFunctionCall = proxyAdminContract.interface.encodeFunctionData("upgrade", [
    contractAddress,
    newImplementationAddress,
  ]);

  console.log(
    `Upgrade transaction proposed for ${contractName} at ${contractAddress} to new implementation at ${newImplementationAddress}`,
  );
  console.log(`When finished run to verify:`);
  console.log(`npx hardhat verify ${newImplementationAddress} --network ${network.name}`);
  console.log("\n");
  

  const to = await proxyAdminContract.getAddress();
  const value ="0"
  const data = encodedFunctionCall;

  return{to, value, data};
}
export default main;
