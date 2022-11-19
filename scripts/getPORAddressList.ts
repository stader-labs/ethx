import { ethers } from 'hardhat'

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)
  const porAddressList = await validatorRegistryInstance.getPoRAddressList()
  console.log('porlist is ', porAddressList)
}
main()
