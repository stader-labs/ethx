import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const permissionLess = process.env.PERMISSION_LESS_POOL
  const staderPoolHelperFactory = await ethers.getContractFactory('StaderPoolHelper')
  const poolHelper = await upgrades.deployProxy(staderPoolHelperFactory, [
    100,
    owner.address,
    permissionLess,
    operatorRegistry,
    validatorRegistry
  ])
  await poolHelper.deployed()
  console.log('Stader pool helper deployed to:', poolHelper.address)
}

main()