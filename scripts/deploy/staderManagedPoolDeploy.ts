import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {

  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT;
  const validatorRegistry = process.env.VALIDATOR_REGISTRY;
  const StaderManagedPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const StaderManagedStakePool = await upgrades.deployProxy(StaderManagedPoolFactory,[
    ethDepositContract,
    validatorRegistry,
    owner.address
  ])
  await StaderManagedStakePool.deployed()
  console.log('StaderManagedStakePool deployed to:', StaderManagedStakePool.address)
}

main()
