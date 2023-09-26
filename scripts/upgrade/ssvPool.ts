import { ethers, upgrades } from 'hardhat'

async function main() {
  const ssvPoolAddress = process.env.SSV_POOL ?? ''
  const ssvPoolFactory = await ethers.getContractFactory('SSVPool')
  const ssvPoolInstance = await ssvPoolFactory.attach(ssvPoolAddress)

  const ssvPoolUpgraded = await upgrades.upgradeProxy(ssvPoolInstance, ssvPoolFactory)

  console.log('SSV Pool proxy address ', ssvPoolUpgraded.address)

  console.log('upgraded SSV Pool contract')
}

main()
