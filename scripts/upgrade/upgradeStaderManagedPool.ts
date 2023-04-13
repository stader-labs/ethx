import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const staderManagedPool = process.env.STADER_MANAGED_POOL ?? ''
  const staderManagedPoolUtils = await ethers.getContractFactory('StaderManagedStakePool')
  const staderManagedPoolInstance = await staderManagedPoolUtils.attach(staderManagedPool)

  const staderContractUpgraded = await upgrades.upgradeProxy(staderManagedPoolInstance, staderManagedPoolUtils)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded Stader Managed Pool')
}

main()
