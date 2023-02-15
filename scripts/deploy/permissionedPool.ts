import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const poolManager = process.env.STADER_STAKING_POOL_MANAGER
  const staderPermissinedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const staderPermissionedPool = await upgrades.deployProxy(staderPermissinedPoolFactory, [
    owner.address,
    ethDepositContract,
    poolManager
  ])
  await staderPermissionedPool.deployed()
  console.log('Stader permissioned Less Pool deployed to:', staderPermissionedPool.address)
}

main()
