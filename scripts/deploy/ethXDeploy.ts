import { ethers } from "hardhat";
const hre = require("hardhat");

async function main() {
	const ethXFactory = await ethers.getContractFactory("ETHX");
	const ethX = await ethXFactory.deploy();
	await ethX.deployed();
	console.log("ethX Token deployed to:", ethX.address);
}

main();
"\r\n"