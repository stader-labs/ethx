import { ethers } from 'hardhat'

async function main() {
  const ssvNodeRegistry = process.env.SSV_NODE_REGISTRY ?? ''
  const ssvNodeRegistryFactory = await ethers.getContractFactory('SSVNodeRegistry')
  const ssvNodeRegistryInstance = await ssvNodeRegistryFactory.attach(ssvNodeRegistry)

  const addKeyTx = await ssvNodeRegistryInstance.addValidatorKeys(['0x8cff5fbae2555829c91a35f8d8cd6218371c8706e0324c617d8cdb27e04f7494cd33a1d484ceb48992770a11113b68ff'], 
  ['0xb6ee3561b8c84737a14768a4e1e03f998de6e4a064a608ec56291c6d73151e459a6a8f96c5e8ff4d52f6df0ef0ecdd7f17af7352c32746c97f9f7154d0f7dec8f4ab023f2d72d5a49cd0f8e74846b860a8f9b0ebb020133c8b32889df52b8f76'], 
  ['0x919435e354be5b878371892afa03295fd981a987795b841d79f8398876535158a2866ce5694995bc0c7ae118f4cb63760f9e005fa8c47e8bea3dfe625ed3701932c64fd6b635d871dd59b25c08eee27e7fee3b1be5b834c9eef8538f8cb57bf6'])

  console.log('added validator keys')
}
main()
