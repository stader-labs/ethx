import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPool = await upgrades.deployProxy(permissionedPoolFactory, [owner.address, staderConfigAddr])
  console.log('permissioned pool deployed to: ', permissionedPool.address)
}

main()
