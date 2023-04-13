import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const insuranceFundFactory = await ethers.getContractFactory('StaderInsuranceFund')
  const insuranceFund = await upgrades.deployProxy(insuranceFundFactory, [owner.address, staderConfigAddr])
  console.log('stader insuranceFund deployed to: ', insuranceFund.address)
}

main()
