import { ethers, upgrades } from "hardhat";
const hre = require("hardhat");

async function main() {

	const validatorRegistryFactory = await ethers.getContractFactory("StaderValidatorRegistry");
	const validatorRegistry = await upgrades.deployProxy(validatorRegistryFactory);

	await validatorRegistry.deployed();
	console.log("StaderValidatorRegistry deployed to:", validatorRegistry.address);

}

main();
"\n"