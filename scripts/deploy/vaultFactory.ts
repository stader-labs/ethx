import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const VaultFactoryContractFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactory = await upgrades.deployProxy(VaultFactoryContractFactory, [owner.address, staderConfigAddr])
  console.log('vaultFactory deployed to: ', vaultFactory.address)
}

main()
