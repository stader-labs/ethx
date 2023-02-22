import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const staderPermissionLessPool = process.env.PERMISSION_LESS_POOL ?? ''
  const staderPermissionLessPoolFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const staderPermissionLessPoolInstance = await staderPermissionLessPoolFactory.attach(staderPermissionLessPool)

  const staderContractUpgraded = await upgrades.upgradeProxy(
    staderPermissionLessPoolInstance,
    staderPermissionLessPoolFactory
  )

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded Stader PermissionLess Pool')
}

main()
