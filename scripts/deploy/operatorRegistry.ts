import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const operatorRegistryFactory = await ethers.getContractFactory('StaderOperatorRegistry')
  const operatorRegistry = await upgrades.deployProxy(operatorRegistryFactory)

  await operatorRegistry.deployed()
  console.log('Stader  operator Registry deployed to:', operatorRegistry.address)
}

main()
