import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {

const [owner] = await ethers.getSigners()
const rewardFactory = process.env.REWARD_FACTORY
const operatorRegistry = process.env.OPERATOR_REGISTRY
  const validatorRegistryFactory = await ethers.getContractFactory('PermissionLessValidatorRegistry')
  const validatorRegistry = await upgrades.deployProxy(validatorRegistryFactory,[owner.address,rewardFactory,operatorRegistry])

  await validatorRegistry.deployed()
  console.log('Stader Validator Registry deployed to:', validatorRegistry.address)
}

main()
