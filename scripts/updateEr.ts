import { ethers } from "hardhat";
import { createStaderManagerInstance } from "./createStaderManagerInstance";

async function main() {
	const ssvManagerInstance = await createStaderManagerInstance();
    // const staketxn = await ssvManagerInstance.stake({value:ethers.utils.parseEther("16")});
    const staketxn = await ssvManagerInstance.updateExchangeRate();
    staketxn.wait();
    console.log("staked succesfully");

}
main();