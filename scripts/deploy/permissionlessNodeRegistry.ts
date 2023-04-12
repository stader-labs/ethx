import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(permissionlessNodeRegistryFactory, [
    owner.address,
    staderConfigAddr,
  ])
  console.log('permissionless node registry deployed to: ', permissionlessNodeRegistry.address)
}

main()
