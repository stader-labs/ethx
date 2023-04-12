import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const socializePool = process.env.SOCIALIZING_POOL ?? ''
  const socializePoolUtils = await ethers.getContractFactory('SocializingPoolContract')
  const socializePoolInstance = await socializePoolUtils.attach(socializePool)

  const staderContractUpgraded = await upgrades.upgradeProxy(socializePoolInstance, socializePoolUtils)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded socializePool')
}

main()
