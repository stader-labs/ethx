import { ethers, upgrades } from 'hardhat'
async function main() {
  const poolFactoryContract = await ethers.getContractFactory('PoolFactory')
  const poolFactoryInstance = await upgrades.deployProxy(poolFactoryContract, [])

  await poolFactoryInstance.deployed()
  console.log('poolFactory deployed to:', poolFactoryInstance.address)
}

main()
