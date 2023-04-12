import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const poolUtilsFactory = await ethers.getContractFactory('PoolUtils')
  const poolUtils = await upgrades.deployProxy(poolUtilsFactory, [owner.address, staderConfigAddr])
  console.log('pool utils deployed to: ', poolUtils.address)
}

main()
