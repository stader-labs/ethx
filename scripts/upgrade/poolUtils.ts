import { ethers, upgrades } from 'hardhat'

async function main() {
  const poolUtils = process.env.POOL_UTILS ?? ''
  const poolUtilsFactory = await ethers.getContractFactory('PoolUtils')
  const poolUtilsInstance = await poolUtilsFactory.attach(poolUtils)

  const poolUtilsUpgraded = await upgrades.upgradeProxy(poolUtilsInstance, poolUtilsFactory)

  console.log('pool utils proxy address ', poolUtilsUpgraded.address)

  console.log('upgraded pool utils contract')
}

main()
