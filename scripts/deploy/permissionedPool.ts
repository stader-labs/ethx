import { ethers, upgrades } from 'hardhat'

async function main() {
  const admin = process.env.EXTERNAL_ADMIN ?? ''
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const permissionedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPool = await upgrades.deployProxy(permissionedPoolFactory, [admin, staderConfigAddr])
  console.log('permissioned pool deployed to: ', permissionedPool.address)
}

main()
