import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const permissionedNodeRegistry = process.env.PERMISSIONED_NODE_REGISTRY ?? ''
  const permissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistryInstance = await permissionedNodeRegistryFactory.attach(permissionedNodeRegistry)

  const permissionedNodeRegistryUpgraded = await upgrades.upgradeProxy(permissionedNodeRegistryInstance, permissionedNodeRegistryFactory)

  console.log('new implementation address ', permissionedNodeRegistryUpgraded.address)

  console.log('upgraded permissioned Node Registry')
}

main()
