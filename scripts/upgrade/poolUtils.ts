import { ethers, upgrades } from 'hardhat'

async function main() {
  const poolUtils = process.env.POOL_UTILS ?? ''
  const poolUtilsFactory = await ethers.getContractFactory('PoolUtils')
  const poolSelectorInstance = await poolUtilsFactory.attach(poolUtils)

  const poolSelectorUpgraded = await upgrades.upgradeProxy(poolSelectorInstance, poolUtilsFactory)

  console.log('pool selector upgraded proxy address ', poolSelectorUpgraded.address)

  console.log('upgraded pool selector contract')
}

main()
