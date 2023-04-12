import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const poolManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const poolManager = await upgrades.deployProxy(poolManagerFactory, [owner.address, staderConfigAddr])
  console.log('stader stake pool manager deployed to: ', poolManager.address)
}

main()
