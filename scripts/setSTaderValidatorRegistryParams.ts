const { ethers } = require('hardhat')

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)

  const ssvPool = process.env.STADER_SSV_STAKING_POOL
  const staderPool = process.env.STADER_MANAGED_POOL

  const setSSVPoolTxn = await validatorRegistryInstance.setStaderSSVStakePoolAddress(ssvPool)
  setSSVPoolTxn.wait()
  console.log('ssv pool address updated')

  const staderPoolTxn = await validatorRegistryInstance.setStaderManagedStakePoolAddress(staderPool)
  staderPoolTxn.wait()
  console.log('stader pool updated')
}

main()
