import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const operatorRegistry = process.env.OPERATOR_REGISTRY ?? ''
  const operatorRegistryFactory = await ethers.getContractFactory('StaderOperatorRegistry')
  const operatorRegistryInstance = await operatorRegistryFactory.attach(operatorRegistry)

  const staderContractUpgraded = await upgrades.upgradeProxy(operatorRegistryInstance, operatorRegistryFactory)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded operator registry')
}

main()
