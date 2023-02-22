const { ethers } = require('hardhat')

async function main() {
  const [owner] = await ethers.getSigners()

  const ethXAddress = process.env.ETHX_CONTRACT
  const poolManager = process.env.STADER_STAKING_POOL_MANAGER
  const socializingPool = process.env.SOCIALIZING_POOL
  const staderManagedPool = process.env.STADER_MANAGED_POOL
  const staderPermissionLessPool = process.env.STADER_PERMISSION_LESS_POOL
  const operatorRegistry = process.env.OPERATOR_REGISTRY
  const validatorRegistry = process.env.VALIDATOR_REGISTRY

  const ethxFactory = await ethers.getContractFactory('ETHX')
  const ethX = await ethxFactory.attach(ethXAddress)

  const minterRole = await ethX.MINTER_ROLE()
  await ethX.grantRole(minterRole, poolManager)
  console.log('level 1')

  const socializePoolFactory = await ethers.getContractFactory('SocializingPoolContract')
  const socializePool = await socializePoolFactory.attach(socializingPool)

  const rewardDistributor = await socializePool.REWARD_DISTRIBUTOR()
  await socializePool.grantRole(rewardDistributor, owner.address)
  console.log('level 2')

  const staderPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const staderPermissionedPool = await staderPoolFactory.attach(staderManagedPool)

  const poolManagerRole = await staderPermissionedPool.STADER_POOL_MANAGER()
  await staderPermissionedPool.grantRole(poolManagerRole, poolManager)
  console.log('level 3')

  const staderPermissionLessPoolFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const staderPermissionLessPoolInstance = await staderPermissionLessPoolFactory.attach(staderPermissionLessPool)

  const poolManagerRolePermissionLessPool = await staderPermissionLessPoolInstance.STADER_POOL_MANAGER()
  await staderPermissionLessPoolInstance.grantRole(poolManagerRolePermissionLessPool, poolManager)
  console.log('level 4')

  const permissionlessOperator = await staderPermissionLessPoolInstance.PERMISSION_LESS_OPERATOR()
  await staderPermissionLessPoolInstance.grantRole(permissionlessOperator, owner.address)
  console.log('level 5')

  const operatorRegistryFactory = await ethers.getContractFactory('StaderOperatorRegistry')
  const operatorRegistryInstance = await operatorRegistryFactory.attach(operatorRegistry)

  const staderNetworkRoleOperatorRegistry = await operatorRegistryInstance.STADER_NETWORK_POOL()
  await operatorRegistryInstance.grantRole(staderNetworkRoleOperatorRegistry, staderManagedPool)
  console.log('level 6')

  await operatorRegistryInstance.grantRole(staderNetworkRoleOperatorRegistry, staderPermissionLessPool)
  console.log('level 7')

  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)

  const staderNetworkRoleValidatorRegistry = await validatorRegistryInstance.STADER_NETWORK_POOL()
  await validatorRegistryInstance.grantRole(staderNetworkRoleValidatorRegistry, staderManagedPool)
  console.log('level 8')

  await validatorRegistryInstance.grantRole(staderNetworkRoleValidatorRegistry, staderPermissionLessPool)
  console.log('level 9')
}

main()
