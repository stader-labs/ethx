import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const poolManager = process.env.STADER_STAKING_POOL_MANAGER
  const staderPermissionLessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const staderPermissionLessPool = await upgrades.deployProxy(staderPermissionLessPoolFactory, [
    owner.address,
    ethDepositContract,
    poolManager
  ])
  await staderPermissionLessPool.deployed()
  console.log('Stader Permission Less Pool deployed to:', staderPermissionLessPool.address)
}

main()
