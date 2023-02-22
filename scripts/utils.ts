import { ethers, upgrades } from 'hardhat'

export async function deployNonUpgradeableContract(contractName: string, ...args: any) {
  const contractFactory = await ethers.getContractFactory(contractName)
  const contract = args.length ? await contractFactory.deploy(...args) : await contractFactory.deploy()
  await contract.deployed()

  console.log(`${contractName} Contract deployed to:`, contract.address)
  return contract.address
}

export async function deployUpgradeableContract(contractName: string, ...args: any) {
  const contractFactory = await ethers.getContractFactory(contractName)
  const contract = args.length
    ? await upgrades.deployProxy(contractFactory, args)
    : await upgrades.deployProxy(contractFactory)
  await contract.deployed()
  const contractImplAddress = await upgrades.erc1967.getImplementationAddress(contract.address)

  console.log(`Proxy ${contractName} deployed to:`, contract.address)
  console.log(`Impl ${contractName} deployed to:`, contractImplAddress)

  return contract.address
}
