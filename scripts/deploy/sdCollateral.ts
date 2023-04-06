import { ethers, upgrades } from 'hardhat'
import { deployNonUpgradeableContract, deployUpgradeableContract } from '../utils'

async function main() {
  const staderConfigAddr = '0xe34c84A15326f7980F59DE6b5A77C57ca2043c48'
  const sdCollateralAddr = await deployUpgradeableContract('SDCollateral', staderConfigAddr)
}

main()
