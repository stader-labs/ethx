import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const validatorWithdrawVaultFactory = await ethers.getContractFactory('ValidatorWithdrawVault')
  const withdrawVault = await upgrades.deployProxy(validatorWithdrawVaultFactory, [owner.address])

  await withdrawVault.deployed()
  console.log('withdrawVault deployed to:', withdrawVault.address)
}

main()
