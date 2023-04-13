import { ethers, upgrades } from 'hardhat'

async function main() {
  const sdCollateral = process.env.SD_COLLATERAL ?? ''
  const sdCollateralFactory = await ethers.getContractFactory('SDCollateral')
  const sdCollateralInstance = await sdCollateralFactory.attach(sdCollateral)

  const sdCollateralUpgraded = await upgrades.upgradeProxy(sdCollateralInstance, sdCollateralFactory)

  console.log('sd collateral proxy address ', sdCollateralUpgraded.address)

  console.log('upgraded sd collateral contract')
}

main()
