import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {

  const [owner] = await ethers.getSigners()
  const rewardFactory = process.env.REWARD_FACTORY
  const socializePool = process.env.SOCIALIZE_POOL
  const operatorRegistryFactory = await ethers.getContractFactory('PermissionLessOperatorRegistry')
  const operatorRegistry = await upgrades.deployProxy(operatorRegistryFactory,[owner.address,rewardFactory,socializePool]);

  await operatorRegistry.deployed()
  console.log('Stader  operator Registry deployed to:', operatorRegistry.address)
}

main();
