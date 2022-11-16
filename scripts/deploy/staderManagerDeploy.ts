import { ethers, upgrades } from "hardhat";
const hre = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    const ethXAddress = process.env.ETHX_CONTRACT;
    const staderManagedPool = process.env.STADER_MANAGED_POOL;
    const staderSSVPool = process.env.STADER_SSV_STAKING_POOL;
    const ethXFactory = await hre.ethers.getContractFactory("ETHX");
    const ethX = await ethXFactory.attach(ethXAddress);
	const stakingManagerFactory = await ethers.getContractFactory("StaderStakePoolsManager");
	const stakingManager = await upgrades.deployProxy(stakingManagerFactory,
        [owner.address,
        ethX.address,
        staderSSVPool,
        staderManagedPool,
        1,
        0])

	await stakingManager.deployed();
	console.log("StaderStakePoolsManager deployed to:", stakingManager.address);

    await ethX.setMinterRole(stakingManager.address);

}



main();