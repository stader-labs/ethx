const { ethers } = require("hardhat");


export async function createStaderManagerInstance() {
	const SSV_MANAGER_CONTRACT = process.env.STADER_STAKING_POOL_MANAGER;
	const staderMangerFactory = await ethers.getContractFactory("StaderStakePoolsManager");
	const staderMangerInstance = await staderMangerFactory.attach(SSV_MANAGER_CONTRACT);
	console.log("Created contract instance");
	return staderMangerInstance;
}