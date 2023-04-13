import { ethers, upgrades } from 'hardhat'

async function main() {
  const permissionedSocializingPool = process.env.PERMISSIONED_SOCIALIZING_POOL ?? ''
  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const permissionedSocializingPoolInstance = await socializingPoolFactory.attach(permissionedSocializingPool)

  const permissionedSocializingPoolUpgraded = await upgrades.upgradeProxy(
    permissionedSocializingPoolInstance,
    socializingPoolFactory
  )

  console.log('permissioned socializing pool proxy address ', permissionedSocializingPoolUpgraded.address)

  console.log('upgraded permissioned socializing pool contract')
}

main()
