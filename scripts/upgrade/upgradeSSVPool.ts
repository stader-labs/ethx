import { ethers, upgrades } from 'hardhat'
const hre = require('hardhat')

async function main() {
  const staderSSVPool = process.env.STADER_SSV_STAKING_POOL ?? ''
  const staderSSVPoolUtils = await ethers.getContractFactory('StaderSSVStakePool')
  const staderSSVPoolInstance = await staderSSVPoolUtils.attach(staderSSVPool)

  const staderContractUpgraded = await upgrades.upgradeProxy(staderSSVPoolInstance, staderSSVPoolUtils)

  console.log('new implementation address ', staderContractUpgraded.address)

  console.log('upgraded Stader SSV Pool')
}

main()
