import { ethers } from "hardhat";
import { createStaderManagerInstance } from "./createStaderManagerInstance";

async function main() {
	const ssvManagerInstance = await createStaderManagerInstance();
    const staketxn = await ssvManagerInstance.stake({value:ethers.utils.parseEther("16")});
    staketxn.wait();
    console.log("staked succesfully");

}
main();
"\r\n"
