import { ethers } from 'hardhat'

async function main() {
    const operatorRegistry = process.env.OPERATOR_REGISTRY??''
    const operatorRegistryFactory = await ethers.getContractFactory('PermissionLessOperatorRegistry')
  const operatorRegistryInstance = await operatorRegistryFactory.attach(operatorRegistry)
  const porAddressList = await operatorRegistryInstance.onboardNodeOperator(false, 'test_0', '0xD2ed9651d3B28f1eeE08B297339914ca7d8171c2')
  
  console.log('onboarded operator');
}
main()
