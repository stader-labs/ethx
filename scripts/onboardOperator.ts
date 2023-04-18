import { ethers } from 'hardhat'

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(
    '0x0DAbF7C540881EbB865fe6b873b667D77601091C'
  )
  const onboardOperatorTx = await permissionlessNodeRegistryInstance.onboardNodeOperator(
    'sanjay-test2',
    '0x1C680c886D2C059890Cc925ef6bcBCc53310Cf06'
  )

  console.log('onboarded operator')
}
main()
