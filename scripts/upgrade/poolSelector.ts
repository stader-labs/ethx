import { ethers, upgrades } from 'hardhat'

async function main() {
  const poolSelector = process.env.POOL_SELECTOR ?? ''
  const poolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelectorInstance = await poolSelectorFactory.attach(poolSelector)

  const poolSelectorUpgraded = await upgrades.upgradeProxy(poolSelectorInstance, poolSelectorFactory)

  console.log('pool selector proxy address ', poolSelectorUpgraded.address)

  console.log('upgraded pool selector contract')
}

main()
