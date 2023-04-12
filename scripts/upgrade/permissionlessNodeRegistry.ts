import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(permissionlessNodeRegistry)

  const permissionlessNodeRegistryUpgraded = await upgrades.upgradeProxy(
    permissionlessNodeRegistryInstance,
    permissionlessNodeRegistryFactory
  )

  console.log('permissionless node registry proxy address ', permissionlessNodeRegistryUpgraded.address)

  console.log('upgraded permissionless node registry')
}

main()
