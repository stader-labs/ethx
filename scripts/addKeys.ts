import { ethers } from 'hardhat'

async function main() {
  const validatorRegistry = process.env.VALIDATOR_REGISTRY ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)
  const porAddressList = await validatorRegistryInstance.addValidatorKeys(['0xb1a91b2556bd3ebe04059dd7753afab6ac73596838a537487fa3dcf3d0645e6b5173929dac838ebaa213cba966832575'],
  ['0xad594b91b8589a88e04f63c05e48afb91b6ec1d2798637f474ba19e253a11c8bac41489728472374d0c967a56059b04d051847dfde86f752348ecd32cbbf77f44fd67b0daff0f99816a7a1b79a127a2f8d576e73b2270a3b0fe62508bf2ed50c'],
  ['0x0aa5fdbf51bc50efdf84be4da6446599532d275baae72afce6ab77dbe975db7e'],{ value: ethers.utils.parseEther('4') })
  console.log('added keys');
}
main()
