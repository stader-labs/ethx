import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const staderPermissionLessPoolFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const staderPermissionLessPool = await upgrades.deployProxy(staderPermissionLessPoolFactory, [
    owner.address,
    ethDepositContract,
    50
  ])
  await staderPermissionLessPool.deployed()
  console.log('Stader Permission Less Pool deployed to:', staderPermissionLessPool.address)
}

main()
