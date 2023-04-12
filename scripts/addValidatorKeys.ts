import { ethers } from 'hardhat'

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(permissionlessNodeRegistry)

  const addKeyTx = await permissionlessNodeRegistryInstance.addValidatorKeys([], [], [], {
    value: ethers.utils.parseEther(''),
  })

  console.log('added validator keys')
}
main()
