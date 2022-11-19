import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const StaderManagedPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const StaderManagedStakePool = await upgrades.deployProxy(StaderManagedPoolFactory)
  await StaderManagedStakePool.deployed()
  console.log('StaderManagedStakePool deployed to:', StaderManagedStakePool.address)
}

main()
