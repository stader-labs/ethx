import { ethers, upgrades } from 'hardhat'

async function main() {
  const vaultFactoryAddress = process.env.VAULT_FACTORY ?? ''
  const vaultContractFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactoryInstance = await vaultContractFactory.attach(vaultFactoryAddress)

  const vaultFactoryUpgraded = await upgrades.upgradeProxy(vaultFactoryInstance, vaultContractFactory)

  console.log('vault factory proxy address ', vaultFactoryUpgraded.address)

  console.log('upgraded vault factory contract')
}

main()
