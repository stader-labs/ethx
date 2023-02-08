import { ethers } from 'hardhat'

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)
  const porAddressList = await validatorRegistryInstance.addValidatorKeys('0xb1a91b2556bd3ebe04059dd7753afab6ac73596838a537487fa3dcf3d0645e6b5173929dac838ebaa213cba966832575',
  '0xb04891165c184470d0fc07f05cbade098f05762fb46774c4aa2095f21009b23b11a04e57ab6e10cf57900c64438e421d0ca2f9929ee6c5769a77669c49f9da6884ff91869bc1cc7b6c25dccaf9fa5f2ddb870b3613001b13ed9f521c31e31e1b',
  '0x7ab5643a0e03bd3258d5adf2aed79d63af926d2dcfd9b62b475709078cac0748',{ value: ethers.utils.parseEther('4') })
  console.log('added keys');
}
main()
