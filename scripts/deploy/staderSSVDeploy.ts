import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ssvNetworkContract = process.env.SSV_NETWORK_CONTRACT
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const ssvToken = process.env.SSV_TOKEN_CONTRACT
  const validatorRegistry = process.env.VALIDATOR_REGISTRY

  const StaderSSVStakePoolFactory = await ethers.getContractFactory('StaderSSVStakePool')
  const stakingManager = await upgrades.deployProxy(StaderSSVStakePoolFactory, [
    ssvNetworkContract,
    ssvToken,
    ethDepositContract,
    validatorRegistry,
    owner.address,
  ])

  await stakingManager.deployed()
  console.log('StaderSSV Pool deployed to:', stakingManager.address)
}

main()
