import { assignOperators } from "./2_assignOperators";
import { distributeKeys } from "./3_distributeKeys";
const bytes32 = require("bytes32");

const { ethers } = require("hardhat");

export async function startWorkflow(
  keystorePass:any,
  operatorIndex:any,
  validatorsNo:any,
): Promise<Array<object>> {
  const newRegistries = [];

  let newOperators;
  let newKeysDistribution;

  try {
    newOperators = await assignOperators();

  } catch (e) {
    console.log("Error while sorting operators", e);
    return [];
  }

  if (newOperators != undefined) {
    for (let i = 1; i < validatorsNo+1; i++) {
      const keystore = require(`./keystores/keystore${i}.json`);
      const deposit = require(`./deposits/deposit${i}.json`)

      try {
        newKeysDistribution = await distributeKeys(
          keystore,
          keystorePass,
          newOperators,
          operatorIndex
        );
      } catch (e) {
        console.log("Error while distributing Keys", e);
      }

      if (newKeysDistribution) {
        try {
          const staderSSVPool = process.env.STADER_SSV_STAKING_POOL ?? ''
          const staderSSVPoolFactory = await ethers.getContractFactory('StaderSSVStakePool')
          const staderSSVPoolInstance = await staderSSVPoolFactory.attach(staderSSVPool)

          newRegistries.push({
            pubKey: newKeysDistribution.pubKey,
            pubShares: newKeysDistribution.publicShares,
            encryptedShares: newKeysDistribution.encryptedShares,
            operatorIds: newKeysDistribution.operatorIds,
          });

          const depositTxn = await staderSSVPoolInstance.depositEthToDepositContract(
            '0x' + deposit.pubkey,
            '0x' + deposit.withdrawal_credentials,
            '0x' + deposit.signature,
            '0x' + deposit.deposit_data_root
          )
          depositTxn.wait(1);

          console.log("deposited 32eth for a validator");

          await staderSSVPoolInstance.registerValidatorToSSVNetwork(
            newKeysDistribution.pubKey,
            newKeysDistribution.publicShares,
            newKeysDistribution.encryptedShares,
            newKeysDistribution.operatorIds,
            ethers.utils.parseEther('10')
          );

          console.log("registered validator with ssv network");


        } catch (e) {
          console.log("Error while adding validator to registry", e);
        }
      }
    }
  }
  return newRegistries;
}
