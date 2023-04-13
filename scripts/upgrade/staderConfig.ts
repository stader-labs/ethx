import { ethers, upgrades } from 'hardhat'

async function main() {
  const staderConfig = process.env.STADER_CONFIG ?? ''
  const staderConfigFactory = await ethers.getContractFactory('StaderConfig')
  const staderConfiglInstance = await staderConfigFactory.attach(staderConfig)

  const staderConfigUpgraded = await upgrades.upgradeProxy(staderConfiglInstance, staderConfigFactory)

  console.log('stader config proxy address ', staderConfigUpgraded.address)

  console.log('upgraded stader config contract')
}

main()
