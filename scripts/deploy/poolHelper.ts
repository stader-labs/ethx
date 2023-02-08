import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const permissionedPool = process.env.PERMISSIONED_POOL
  const permissionLess = process.env.PERMISSION_LESS_POOL
  const staderPoolHelperFactory = await ethers.getContractFactory('StaderPoolHelper')
  const poolHelper = await upgrades.deployProxy(staderPoolHelperFactory, [
    owner.address,
    permissionedPool,
    permissionLess,
  ])
  await poolHelper.deployed()
  console.log('Stader pool helper deployed to:', poolHelper.address)
}

main()