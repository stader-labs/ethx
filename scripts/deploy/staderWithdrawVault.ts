import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const validatorWithdrawalVaultFactory = await ethers.getContractFactory('ValidatorWithdrawalVault')
  const withdrawVault = await upgrades.deployProxy(validatorWithdrawalVaultFactory, [owner.address])

  await withdrawVault.deployed()
  console.log('withdrawVault deployed to:', withdrawVault.address)
}

main()
