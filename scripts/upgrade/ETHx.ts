import { ethers, upgrades } from 'hardhat'

async function main() {
  const ETHx = process.env.ETHx ?? ''
  const ETHxFactory = await ethers.getContractFactory('ETHx')
  const ETHxInstance = await ETHxFactory.attach(ETHx)

  const ethXUpgraded = await upgrades.upgradeProxy(ETHxInstance, ETHxFactory)

  console.log('ETHx proxy address ', ethXUpgraded.address)

  console.log('upgraded ETHx contract')
}

main()
