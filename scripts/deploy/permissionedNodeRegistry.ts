import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const vaultFactory = process.env.VAULT_FACTORY
  const socializePool = process.env.SOCIALIZE_POOL
  const PermissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(PermissionedNodeRegistryFactory, [
    owner.address,
    vaultFactory,
    socializePool,
  ])

  await permissionedNodeRegistry.deployed()
  console.log('permissioned Node Registry deployed to:', permissionedNodeRegistry.address)
}

main()
