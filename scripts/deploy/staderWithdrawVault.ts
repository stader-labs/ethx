import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const staderWithdrawVaultFactory = await ethers.getContractFactory('StaderWithdrawVault')
  const withdrawVault = await upgrades.deployProxy(staderWithdrawVaultFactory,[owner.address])

  await withdrawVault.deployed()
  console.log('withdrawVault deployed to:', withdrawVault.address)
}

main()