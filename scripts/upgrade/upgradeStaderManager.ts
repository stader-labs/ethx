import { ethers, upgrades } from "hardhat";
const hre = require("hardhat");

async function main() {
  const staderContract = process.env.STADER_STAKING_POOL_MANAGER??'';
  const staderFactory = await ethers.getContractFactory("StaderStakePoolsManager");
  const staderManagerInstance = await staderFactory.attach(staderContract);

  const staderContractUpgraded = await upgrades.upgradeProxy(
    staderManagerInstance,
    staderFactory
  );

  console.log("new implementation address ", staderContractUpgraded.address);

  console.log("upgraded Stader Contract");
}

main();