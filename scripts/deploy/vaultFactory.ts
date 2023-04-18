import { ethers, upgrades } from 'hardhat'

async function main() {
  const admin = process.env.EXTERNAL_ADMIN ?? ''
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const VaultFactoryContractFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactory = await upgrades.deployProxy(VaultFactoryContractFactory, [admin, staderConfigAddr])
  console.log('vaultFactory deployed to: ', vaultFactory.address)
}

main()
