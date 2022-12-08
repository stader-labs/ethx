import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const staderManagedPool = process.env.STADER_MANAGED_POOL ?? ''
  const staderManagedPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const staderManagedPoolInstance = await staderManagedPoolFactory.attach(staderManagedPool)

  const staderContractUpgraded = await upgrades.upgradeProxy(staderManagedPoolInstance, staderManagedPoolFactory)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded Stader Managed Pool')
}

main()
