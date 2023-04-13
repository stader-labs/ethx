import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT ?? ''

  const staderConfigFactory = await ethers.getContractFactory('StaderConfig')
  const staderConfig = await upgrades.deployProxy(staderConfigFactory, [owner.address, ethDepositContract])
  console.log('staderConfig deployed to: ', staderConfig.address)
}

main()
