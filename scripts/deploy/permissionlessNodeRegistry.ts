import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const vaultFactory = process.env.VAULT_FACTORY
  const socializePool = process.env.SOCIALIZE_POOL
  const PermissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(PermissionlessNodeRegistryFactory, [
    owner.address,
    vaultFactory,
    socializePool,
  ])

  await permissionlessNodeRegistry.deployed()
  console.log('permissionless Node Registry deployed to:', permissionlessNodeRegistry.address)
}

main()
