import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''
  const ratedOracle = process.env.RATED_ORACLE ?? ''
  const penaltyFactory = await ethers.getContractFactory('Penalty')
  const penaltyContract = await upgrades.deployProxy(penaltyFactory, [owner.address, staderConfigAddr, ratedOracle])
  console.log('penalty contract deployed to: ', penaltyContract.address)
}

main()
