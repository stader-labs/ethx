import { assignOperators } from './ssvOperatorAssign'
import { distributeKeys } from './ssvKeyDistribute'
const bytes32 = require('bytes32')

const { ethers } = require('hardhat')

export async function startWorkflow(
  keystorePass: any,
  operatorIndex: any,
  validatorsNo: any,
  staderSSVInstance: any
): Promise<Array<object>> {
  const newRegistries = []

  let newOperators
  let newKeysDistribution

  try {
    newOperators = await assignOperators()
  } catch (e) {
    console.log('Error while sorting operators', e)
    return []
  }

  if (newOperators != undefined) {
    for (let i = 5; i < validatorsNo + 5; i++) {
      const keystore = require(`../../scripts/keystores/keystore${i}.json`)

      try {
        newKeysDistribution = await distributeKeys(keystore, keystorePass, newOperators, operatorIndex)
      } catch (e) {
        console.log('Error while distributing Keys', e)
      }

      if (newKeysDistribution) {
        try {
          const staderSSVPoolFactory = await ethers.getContractFactory('StaderSSVStakePool')
          const staderSSVPoolInstance = await staderSSVPoolFactory.attach(staderSSVInstance)

          newRegistries.push({
            pubKey: newKeysDistribution.pubKey,
            pubShares: newKeysDistribution.publicShares,
            encryptedShares: newKeysDistribution.encryptedShares,
            operatorIds: newKeysDistribution.operatorIds,
          })

          await staderSSVPoolInstance.registerValidatorToSSVNetwork(
            newKeysDistribution.pubKey,
            newKeysDistribution.publicShares,
            newKeysDistribution.encryptedShares,
            newKeysDistribution.operatorIds,
            ethers.utils.parseEther('10')
          )

          console.log('registered validator with ssv network')
        } catch (e) {
          console.log('Error while adding validator to registry', e)
        }
      }
    }
  }
  return newRegistries
}
