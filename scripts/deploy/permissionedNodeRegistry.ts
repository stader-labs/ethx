import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(permissionedNodeRegistryFactory, [
    owner.address,
    staderConfigAddr,
  ])
  console.log('permissioned node registry deployed to: ', permissionedNodeRegistry.address)
}

main()
