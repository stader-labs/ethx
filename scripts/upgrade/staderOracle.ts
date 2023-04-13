import { ethers, upgrades } from 'hardhat'

async function main() {
  const staderOracle = process.env.STADER_ORACLE ?? ''
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracleInstance = await staderOracleFactory.attach(staderOracle)

  const staderOracleUpgraded = await upgrades.upgradeProxy(staderOracleInstance, staderOracleFactory)

  console.log('stader oracle proxy address ', staderOracleUpgraded.address)

  console.log('upgraded stader oracle contract')
}

main()
