import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const stakePoolManager = process.env.STADER_STAKING_POOL_MANAGER
  const ELRewardFactory = await ethers.getContractFactory('ExecutionLayerRewardContract')
  const ELRewardContract = await upgrades.deployProxy(ELRewardFactory, [stakePoolManager, owner.address])

  await ELRewardContract.deployed()
  console.log('ELRewardContract deployed to:', ELRewardContract.address)
}

main()
