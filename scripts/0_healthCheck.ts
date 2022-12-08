import "dotenv/config";
const readline = require("readline");
const { ethers } = require("hardhat");
const fs = require("fs");
const dir = "scripts/keystores";
import { startWorkflow } from "./1_workflowManager";

const PROVIDER_URL = process.env.PROVIDER_URL;
const KEYSTORE_PASSWORD = process.env.KEYSTORE_PASSWORD;
const staderSSVPool = process.env.STADER_SSV_STAKING_POOL ?? ''
const OPERATOR_INDEX = 0;

async function main() {
  const provider = new ethers.providers.JsonRpcProvider(PROVIDER_URL);
  const staderSSVPoolFactory = await ethers.getContractFactory('StaderSSVStakePool')
  const staderSSVPoolInstance = await staderSSVPoolFactory.attach(staderSSVPool)

  const ssvPoolBalance = await provider.getBalance(
    staderSSVPoolInstance.address
  );

  const ssvPoolAvailableValidators = Math.floor(
    parseInt(ssvPoolBalance) / (32 * 10 ** 18)
  );

  console.log({
    availableEthOnManager: parseInt(ssvPoolBalance),
    availableNumberOfValidatorsOnManager: ssvPoolAvailableValidators,
    balanceOfPool: Number(ssvPoolBalance) / 10 ** 18,
  });

  const numberOfKeystores = fs.readdirSync(dir).length;

  if (numberOfKeystores < ssvPoolAvailableValidators) {
    throw `[ERROR] Number of validators ${ssvPoolAvailableValidators} to process and keystore files ${numberOfKeystores} number mismatch`;
  }

  const registered = await startWorkflow(
    KEYSTORE_PASSWORD,
    OPERATOR_INDEX,
    ssvPoolAvailableValidators,
  );

  console.log("Registered validators: ", registered);
  console.log("Validator added count ", registered.length);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
