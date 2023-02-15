import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
    const [owner] = await ethers.getSigners()
  const rewardContractFactory = await ethers.getContractFactory('VaultFactory')
  const rewardFactoryInstance = await upgrades.deployProxy(rewardContractFactory,[owner.address,owner.address,owner.address])

  await rewardFactoryInstance.deployed()
  console.log('reward Factory deployed to:', rewardFactoryInstance.address)
}

main()