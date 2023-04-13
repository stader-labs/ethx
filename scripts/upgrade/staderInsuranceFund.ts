import { ethers, upgrades } from 'hardhat'

async function main() {
  const insuranceFund = process.env.STADER_INSURANCE_FUND ?? ''
  const insuranceFundFactory = await ethers.getContractFactory('StaderInsuranceFund')
  const insuranceFundInstance = await insuranceFundFactory.attach(insuranceFund)

  const insuranceFundUpgraded = await upgrades.upgradeProxy(insuranceFundInstance, insuranceFundFactory)

  console.log('stader insuranceFund proxy address ', insuranceFundUpgraded.address)

  console.log('upgraded stader insuranceFund contract')
}

main()
