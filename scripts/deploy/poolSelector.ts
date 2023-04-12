import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const poolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelector = await upgrades.deployProxy(poolSelectorFactory, [owner.address, staderConfigAddr])
  console.log('pool selector deployed to: ', poolSelector.address)
}

main()
