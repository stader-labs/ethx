import { ethers, upgrades } from 'hardhat'

async function main() {
  const userWithdrawManager = process.env.USER_WITHDRAW_MANAGER ?? ''
  const userWithdrawManagerFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawManagerInstance = await userWithdrawManagerFactory.attach(userWithdrawManager)

  const userWIthdrawManagerUpgraded = await upgrades.upgradeProxy(
    userWithdrawManagerInstance,
    userWithdrawManagerFactory
  )

  console.log('user withdraw manager proxy address ', userWIthdrawManagerUpgraded.address)

  console.log('upgraded user withdraw manager contract')
}

main()
