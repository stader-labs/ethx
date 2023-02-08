import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = validatorRegistryFactory.attach(validatorRegistry)

  const staderContractUpgraded = await upgrades.upgradeProxy(validatorRegistryInstance, validatorRegistryFactory)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded validator registry')
}

main()
