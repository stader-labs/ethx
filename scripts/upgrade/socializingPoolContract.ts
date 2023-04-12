import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const socializingPool = await upgrades.deployProxy(socializingPoolFactory, [owner.address, staderConfigAddr])
  console.log('socializingPool deployed to: ', socializingPool.address)
}

main()
