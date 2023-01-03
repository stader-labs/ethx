import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const oracle = process.env.ORACLE ?? ''
  const oracleFactory = await ethers.getContractFactory('StaderOracle')
  const oracleInstance = await oracleFactory.attach(oracle)

  const staderContractUpgraded = await upgrades.upgradeProxy(oracleInstance, oracleFactory)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded oracle')
}

main()
