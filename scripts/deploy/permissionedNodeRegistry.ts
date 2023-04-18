import { ethers, upgrades } from 'hardhat'

async function main() {
  const admin = process.env.EXTERNAL_ADMIN ?? ''
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(permissionedNodeRegistryFactory, [
    admin,
    staderConfigAddr,
  ])
  console.log('permissioned node registry deployed to: ', permissionedNodeRegistry.address)

  const permissionedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPool = await upgrades.deployProxy(permissionedPoolFactory, [admin, staderConfigAddr])
  console.log('permissioned pool deployed to: ', permissionedPool.address)
}

main()
