import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const sdRewardManagerFactory = await ethers.getContractFactory('SDRewardManager')
  const sdRewardManager = await upgrades.deployProxy(sdRewardManagerFactory, [staderConfigAddr])
  console.log('SDRewardManager deployed to: ', sdRewardManager.address)
}

main()
