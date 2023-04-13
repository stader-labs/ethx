import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const ethXFactory = await ethers.getContractFactory('ETHX')
  const ethX = await upgrades.deployProxy(ethXFactory, [owner.address, staderConfigAddr])
  console.log('ethX Token deployed to: ', ethX.address)
}

main()
