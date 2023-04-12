import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionlessPool = process.env.PERMISSIONLESS_POOL ?? ''
  const permissionlessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const permissionlessPoolInstance = await permissionlessPoolFactory.attach(permissionlessPool)

  const permissionlessPoolUpgraded = await upgrades.upgradeProxy(permissionlessPoolInstance, permissionlessPoolFactory)

  console.log('permissionlessPool proxy address ', permissionlessPoolUpgraded.address)

  console.log('upgraded permissionlessPool contracts')
}

main()
