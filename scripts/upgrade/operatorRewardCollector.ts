import { ethers, upgrades } from 'hardhat'

async function main() {
  const operatorRewardCollectorFactory = await ethers.getContractFactory('OperatorRewardsCollector')
  const operatorRewardCollector = await upgrades.deployImplementation(operatorRewardCollectorFactory)
  console.log('operator reward collector at ', operatorRewardCollector)
}

main()
