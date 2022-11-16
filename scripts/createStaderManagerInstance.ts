const { ethers } = require("hardhat");

const SSV_MANAGER_CONTRACT = process.env.STADER_STAKING_POOL_MANAGER;
const SSV_MANAGER_CONTRACT_ABI = require("../artifacts/contracts/StaderStakePoolsManager.sol/StaderStakePoolsManager.json");

export async function createStaderManagerInstance() {
	const [signer] = await ethers.getSigners();
	const ssvManagerInstance = new ethers.Contract(
		SSV_MANAGER_CONTRACT,
		SSV_MANAGER_CONTRACT_ABI.abi,
		signer
	);
	console.log("Created contract instance");
	return ssvManagerInstance;
}