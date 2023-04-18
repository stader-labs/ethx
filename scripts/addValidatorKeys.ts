import { ethers } from 'hardhat'

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(
    '0x0DAbF7C540881EbB865fe6b873b667D77601091C'
  )

  const addKeyTx = await permissionlessNodeRegistryInstance.addValidatorKeys(
    ['0x88e8b2704e1d3bff0e7e3b8a83035fb261df8256aa79831058e99f8fb5284ab5b222ad3fa8367618f2d60141b17a4c38'],
    [
      '0x9524978953f257cc0bcddcd2abeea44b0990f1d92edcfc3662e2b8b2b1586303c694fd1f6c3dde97336bf5cac2c2b89d162c989e24857b70f8b5fb581a5518497a3c3e46a174f9cdab931c754455efb8a0737b9b19993134f9fef395c29d31de',
    ],
    [
      '0x9524978953f257cc0bcddcd2abeea44b0990f1d92edcfc3662e2b8b2b1586303c694fd1f6c3dde97336bf5cac2c2b89d162c989e24857b70f8b5fb581a5518497a3c3e46a174f9cdab931c754455efb8a0737b9b19993134f9fef395c29d31de',
    ]
  )

  console.log('added validator keys')
}
main()
