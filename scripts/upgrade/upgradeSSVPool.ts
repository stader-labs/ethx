import { ethers, upgrades } from "hardhat";
const hre = require("hardhat");

async function main() {
    const staderSSVPool = process.env.STADER_SSV_STAKING_POOL ??'';
    const staderSSVPoolFactory = await ethers.getContractFactory("StaderSSVStakePool");
    const staderSSVPoolInstance = await staderSSVPoolFactory.attach(staderSSVPool);

    const staderContractUpgraded = await upgrades.upgradeProxy(
        staderSSVPoolInstance,
        staderSSVPoolFactory
    );

    console.log("new implementation address ", staderContractUpgraded.address);

    console.log("upgraded Stader SSV Pool");
}

main();


