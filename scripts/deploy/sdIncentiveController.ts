import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const sdIncentiveControllerFactory = await ethers.getContractFactory('SDIncentiveController')
  const sdIncentiveController = await upgrades.deployProxy(sdIncentiveControllerFactory, [
    owner,
    staderConfigAddr,
  ])
  console.log('SD Incentive Controller deployed to: ', sdIncentiveController.address)
}

main()
