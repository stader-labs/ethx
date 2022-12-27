import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const oracleFactory = await ethers.getContractFactory('StaderOracle')
  const oracle = await upgrades.deployProxy(oracleFactory)

  await oracle.deployed()
  console.log('Stader oracle deployed to:', oracle.address)
}

main()
