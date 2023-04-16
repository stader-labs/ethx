import { ethers } from 'hardhat'

async function main() {
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach(permissionlessNodeRegistry)

  const addKeyTx = await permissionlessNodeRegistryInstance.markValidatorReadyToDeposit(
    [
      '0xa7354412be74304f5627a2883c16eae488b92612a21692d5e9fc3ada31281f83a5303e646157434962d3b2cec49503b2',
      '0xa01d74b3ca0d22a53b89c855e39783e07918b868eaf6aa8cfc1e623d18648e8ea4cd24fb4de08852b02a48605150294c',
    ],
    ['0xa867ed85d366e07ded8b06a0e5a3b5b24f6e9a1d43d369985933bbc157eb08ef5579c403c0d75be1e6260ec73ea98a67'],
    ['0xa27f3df5ef9247ee4362107acf4800628d00557602db541c3dd2ad3434c71011e06a6af286a7bd336a674ecabf3ed558']
  )

  console.log('marked keys ready to deposit')
}
main()
