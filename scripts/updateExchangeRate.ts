const { ethers } = require('hardhat')

import { createStaderManagerInstance } from './createStaderManagerInstance'
import { validatorBalaceQuery } from './getBeaconChainBalance'

const PROVIDER_URL = process.env.PROVIDER_URL

async function main() {
  const provider = new ethers.providers.JsonRpcProvider(PROVIDER_URL)

  const stakingPoolManager = await createStaderManagerInstance()
  const staderManagedStakePool = process.env.STADER_MANAGED_POOL
  const ssvPool = process.env.STADER_SSV_STAKING_POOL
  let tvl = Number(await provider.getBalance(stakingPoolManager.address))
  tvl += Number(await provider.getBalance(staderManagedStakePool)) + Number(await provider.getBalance(ssvPool))

  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)

  let beaconChainBalance = 0

  const validatorCount = await validatorRegistryInstance.validatorCount()
  console.log('validator count is ', validatorCount)
  for (let i = 0; i < validatorCount; i++) {
    const validator = await validatorRegistryInstance.validatorRegistry(i)
    const validatorbalance = Number(await validatorBalaceQuery(validator.pubKey))
    beaconChainBalance += validatorbalance
  }

  tvl += beaconChainBalance

  // const updateExchangeRateTxn = await stakingPoolManager.updateExchangeRate(tvl.toString(),beaconChainBalance.toString());
  // updateExchangeRateTxn.wait(1);
  console.log(`Exchange Rate updated with tvl  ${tvl.toString()} and beaconBalance ${beaconChainBalance.toString()}`)
}

main()
