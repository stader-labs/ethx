import { ethers } from 'hardhat'

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('PermissionLessValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)
  // const porAddressList = await validatorRegistryInstance.addValidatorKeys('0x80b6fc1815407e009a48f02a1dcae0934927b86855ddccb91c2b5cf20d658256986e4996e5d34ef40deba358d7b94162',
  // '0x873ffefed0334f07e7bd4356e8cb01902eddc80600a2da51feb66c3359491f470df4b603ba9822809b112cd66efe2123032d80ffdbb448da137952b4f235f8635e6bf31313d1320640a2420a2a43d615564b2b57c73da17178f64c2b5c3f7b39',
  // '0x0becaf15c2f7d2d7e8247eeb88e31a3b41636d2bce9c7880a5b3d08ac655c443',{ value: ethers.utils.parseEther('4') })
  console.log('added keys');

}
main()
