import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionlessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const permissionlessPool = await upgrades.deployProxy(permissionlessPoolFactory, [owner.address, staderConfigAddr])
  console.log('permissionless pool deployed to: ', permissionlessPool.address)
}

main()
