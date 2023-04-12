import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionedNodeRegistry = process.env.PERMISSIONED_NODE_REGISTRY ?? ''
  const permissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistryInstance = await permissionedNodeRegistryFactory.attach(permissionedNodeRegistry)

  const permissionedNodeRegistryUpgraded = await upgrades.upgradeProxy(
    permissionedNodeRegistryInstance,
    permissionedNodeRegistryFactory
  )

  console.log('permissioned node registry proxy address ', permissionedNodeRegistryUpgraded.address)

  console.log('upgraded permissioned node registry')
}

main()
