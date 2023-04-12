import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const sdCollateralFactory = await ethers.getContractFactory('SDCollateral')
  const sdCollateral = await upgrades.deployProxy(sdCollateralFactory, [owner.address, staderConfigAddr])
  console.log('SD Collateral deployed to: ', sdCollateral.address)
}

main()
