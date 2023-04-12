import { ethers, upgrades } from 'hardhat'

async function main() {
  const penalty = process.env.PENALTY ?? ''
  const penaltyFactory = await ethers.getContractFactory('Penalty')
  const penaltyInstance = await penaltyFactory.attach(penalty)

  const penaltyUpgraded = await upgrades.upgradeProxy(penaltyInstance, penaltyFactory)

  console.log('penalty proxy address ', penaltyUpgraded.address)

  console.log('upgraded penalty contract')
}

main()
