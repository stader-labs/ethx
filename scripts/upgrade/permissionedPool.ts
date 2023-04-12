import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionedPool = process.env.PERMISSIONED_POOL ?? ''
  const permissionedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPoolInstance = await permissionedPoolFactory.attach(permissionedPool)

  const permissionedPoolUpgraded = await upgrades.upgradeProxy(permissionedPoolInstance, permissionedPoolFactory)

  console.log('permissionedPool proxy address ', permissionedPoolUpgraded.address)

  console.log('upgraded permissionedPool contracts')
}

main()
