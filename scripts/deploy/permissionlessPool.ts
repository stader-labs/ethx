import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const withdrawCred = process.env.WITHDRAW_CRED
  const staderPermissionLessPoolFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const staderPermissionLessPool = await upgrades.deployProxy(staderPermissionLessPoolFactory, [
    withdrawCred,
    ethDepositContract,
    operatorRegistry,
    validatorRegistry,
    owner.address,
  ])
  await staderPermissionLessPool.deployed()
  console.log('Stader Permission Less Pool deployed to:', staderPermissionLessPool.address)
}

main()
