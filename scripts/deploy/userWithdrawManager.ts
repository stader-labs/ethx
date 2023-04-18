import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const userWithdrawalManagerFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawalManager = await upgrades.deployImplementation(userWithdrawalManagerFactory)
  console.log('userWithdrawalManager deployed to: ', userWithdrawalManager)
}

main()
