import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const stakePoolManager = process.env.STADER_STAKING_POOL_MANAGER
  const socializingPoolFactory = await ethers.getContractFactory('SocializingPoolContract')
  const socializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    operatorRegistry,
    validatorRegistry,
    stakePoolManager,
    owner.address,
    owner.address,
  ])

  await socializingPoolContract.deployed()
  console.log('socializingPool deployed to:', socializingPoolContract.address)
}

main()
