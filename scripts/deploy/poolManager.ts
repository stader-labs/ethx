import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethXAddress = process.env.ETHX_CONTRACT
  const oracle = process.env.STADER_ORACLE
  const userWithdrawManager = process.env.WITHDRAW_MANAGER

  const ethXFactory = await hre.ethers.getContractFactory('ETHX')
  const ethX = await ethXFactory.attach(ethXAddress)
  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const stakingManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethX.address,
    oracle,
    userWithdrawManager,
    [owner.address, owner.address],
    [owner.address, owner.address],
    owner.address,
    10,
  ])

  await stakingManager.deployed()
  console.log('Stader Stake Pools Manager deployed to:', stakingManager.address)

  // await ethX.setMinterRole(stakingManager.address)
}

main()
