import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(permissionlessNodeRegistry)

  const permissionlessNodeRegistryUpgraded = await upgrades.upgradeProxy(
    permissionlessNodeRegistryInstance,
    permissionlessNodeRegistryFactory
  )

  console.log('new implementation address ', permissionlessNodeRegistryUpgraded.address)

  console.log('upgraded permission less Node Registry')
}

main()
