import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const userWithdrawFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawManager = await upgrades.deployProxy(userWithdrawFactory, [owner.address])

  await userWithdrawManager.deployed()
  console.log('user Withdraw Manager deployed to:', userWithdrawManager.address)
}

main()
