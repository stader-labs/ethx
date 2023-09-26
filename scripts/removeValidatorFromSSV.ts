import { ethers } from 'hardhat'
import BigNumber from 'bignumber.js';

async function main() {
  const ssVNodeRegistry = process.env.SSV_NODE_REGISTRY ?? ''
  const ssvNodeRegistryFactory = await ethers.getContractFactory('SSVNodeRegistry')
  const ssvNodeRegistryInstance = await ssvNodeRegistryFactory.attach(ssVNodeRegistry)

  interface Cluster {
    validatorCount: number
    networkFeeIndex: number
    index: number
    active: boolean
    balance: BigNumber
  }


  const input1: Cluster = {
    validatorCount: 4,
    networkFeeIndex: 0,
    index: 0,
    active: true,
    balance: ethers.utils.parseEther("40"),
  }

  const input2: Cluster = {
    validatorCount: 3,
    networkFeeIndex: 0,
    index: 0,
    active: true,
    balance: ethers.utils.parseEther("40"),
  }

  const addKeyTx = await ssvNodeRegistryInstance.removeValidatorFromSSVNetwork(
    ['0x8cff5fbae2555829c91a35f8d8cd6218371c8706e0324c617d8cdb27e04f7494cd33a1d484ceb48992770a11113b68ff',
    '0x8ffa518de86de59dd92a7559c1d19dfb92961e8954aa601fe30502aec61af7b55c544366c1ba78fe8e03cdc57d9fbb12'],
    [input1,input2])

  console.log('removed validator keys')
}
main()
