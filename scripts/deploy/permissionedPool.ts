import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const withdrawCred = process.env.WITHDRAW_CRED
  const staderManagedPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const staderManagedStakePool = await upgrades.deployProxy(staderManagedPoolFactory, [
    withdrawCred,
    ethDepositContract,
    operatorRegistry,
    validatorRegistry,
    owner.address,
  ])
  await staderManagedStakePool.deployed()
  console.log('Stader Permission Pool deployed to:', staderManagedStakePool.address)
}

main()
