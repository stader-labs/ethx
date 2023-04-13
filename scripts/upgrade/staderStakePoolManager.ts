import { ethers, upgrades } from 'hardhat'

async function main() {
  const poolManager = process.env.STAKE_POOL_MANAGER ?? ''
  const poolManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const poolManagerInstance = await poolManagerFactory.attach(poolManager)

  const poolManagerUpgraded = await upgrades.upgradeProxy(poolManagerInstance, poolManagerFactory)

  console.log('stader stake pool manager proxy address ', poolManagerUpgraded.address)

  console.log('upgraded stader stake pool manager contract')
}

main()
