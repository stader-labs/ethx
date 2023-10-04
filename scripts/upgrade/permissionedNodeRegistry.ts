import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')

  const permissionedNodeRegistryUpgraded = await upgrades.deployImplementation(permissionedNodeRegistryFactory)

  console.log('permissioned node registry proxy address ', permissionedNodeRegistryUpgraded)

  console.log('upgraded permissioned node registry')
}

main()
