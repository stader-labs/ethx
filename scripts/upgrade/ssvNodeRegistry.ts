import { ethers, upgrades } from 'hardhat'

async function main() {
  const ssvNodeRegistryAddress = process.env.SSV_NODE_REGISTRY ?? ''
  const ssvNodeRegistryFactory = await ethers.getContractFactory('SSVNodeRegistry')
  const ssvNodeRegistryInstance = await ssvNodeRegistryFactory.attach(ssvNodeRegistryAddress)

  const ssvNodeRegistryUpgraded = await upgrades.upgradeProxy(ssvNodeRegistryInstance, ssvNodeRegistryFactory)

  console.log('SSV NodeRegistry proxy address ', ssvNodeRegistryUpgraded.address)

  console.log('upgraded SSV NodeRegistry contract')
}

main()
