import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracle = await upgrades.deployProxy(staderOracleFactory, [owner.address, staderConfigAddr])
  console.log('staderOracle deployed to: ', staderOracle.address)
}

main()
