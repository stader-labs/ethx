import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethXAddress = process.env.ETHX_CONTRACT
  const staderManagedPool = process.env.STADER_MANAGED_POOL
  const staderPermissionLessPool = process.env.STADER_PERMISSION_LESS_POOL
  const ethXFactory = await hre.ethers.getContractFactory('ETHX')
  const ethX = await ethXFactory.attach(ethXAddress)
  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const stakingManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethX.address,
    staderPermissionLessPool,
    staderManagedPool,
    0,
    100,
    10,
    [owner.address, owner.address],
    [owner.address, owner.address],
    owner.address,
  ])

  await stakingManager.deployed()
  console.log('Stader Stake Pools Manager deployed to:', stakingManager.address)

  // await ethX.setMinterRole(stakingManager.address)
}

main()
