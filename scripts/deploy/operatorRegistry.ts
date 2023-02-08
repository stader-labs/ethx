import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {

  const [owner] = await ethers.getSigners()
  const rewardFactory = process.env.REWARD_FACTORY
  const operatorRegistryFactory = await ethers.getContractFactory('StaderOperatorRegistry')
  console.log('owner address' ,owner.address);
  console.log('rewardFactory', rewardFactory);
  const operatorRegistry = await upgrades.deployProxy(operatorRegistryFactory,[rewardFactory,owner.address,owner.address]);

  await operatorRegistry.deployed()
  console.log('Stader  operator Registry deployed to:', operatorRegistry.address)
}

main();
