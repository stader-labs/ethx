import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const stakePoolManager = process.env.STADER_STAKING_POOL_MANAGER
  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const socializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    owner.address,
    stakePoolManager,
    owner.address,
  ])

  await socializingPoolContract.deployed()
  console.log('socializingPool deployed to:', socializingPoolContract.address)
}

main()
