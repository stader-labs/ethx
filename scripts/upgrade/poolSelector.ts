import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const poolSelector = process.env.POOL_SELECTOR ?? ''
  const poolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelectorFactoryInstance = await poolSelectorFactory.attach(poolSelector)

  const poolSelectorFactoryUpgraded = await upgrades.upgradeProxy(poolSelectorFactoryInstance, poolSelectorFactory)

  console.log('new implementation address ', poolSelectorFactoryUpgraded.address)

  console.log('upgraded pool Selector')
}

main()
