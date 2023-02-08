import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const rewardFactory = process.env.REWARD_FACTORY
  const staderManagedPoolFactory = await ethers.getContractFactory('StaderPermissionedStakePool')
  const staderManagedStakePool = await upgrades.deployProxy(staderManagedPoolFactory, [
    ethDepositContract,
    operatorRegistry,
    validatorRegistry,
    owner.address,
    rewardFactory
  ])
  await staderManagedStakePool.deployed()
  console.log('Stader Permission Pool deployed to:', staderManagedStakePool.address)
}

main()
