import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {

  const rewardFactory = process.env.REWARD_FACTORY
const operatorRegistry = process.env.OPERATOR_REGISTRY
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistry = await upgrades.deployProxy(validatorRegistryFactory,[rewardFactory,operatorRegistry])

  await validatorRegistry.deployed()
  console.log('Stader Validator Registry deployed to:', validatorRegistry.address)
}

main()
