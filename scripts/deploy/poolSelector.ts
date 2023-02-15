import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const permissionlessPool = process.env.PERMISSION_LESS_POOL
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY

  const permissionedPool = process.env.PERMISSIONED_POOL
  const permissionedNodeRegistry = process.env.PERMISSIONED_NODE_REGISTRY

  const staderPoolHelperFactory = await ethers.getContractFactory('PoolSelector')
  const poolHelper = await upgrades.deployProxy(staderPoolHelperFactory, [
    100,
    0,
    owner.address,
    permissionlessPool,
    permissionlessNodeRegistry,
    permissionedPool,
    permissionedNodeRegistry
  ])
  await poolHelper.deployed()
  console.log('Stader pool selector deployed to:', poolHelper.address)
}

main()