import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const sdUtilityPoolFactory = await ethers.getContractFactory('SDUtilityPool')
  const sdUtilityPool = await upgrades.deployProxy(sdUtilityPoolFactory, [
    owner,
    staderConfigAddr,
  ])
  console.log('Utility pool deployed to: ', sdUtilityPool.address)
}

main()
