import { ethers, upgrades } from 'hardhat'

async function main() {
  const [staderOwner] = await ethers.getSigners()
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracle = await upgrades.deployProxy(staderOracleFactory)

  console.log('stader oracle deployed at ', staderOracle.address)

  const ETHxToken = await ethers.getContractFactory('ETHX')
  const ethxToken = await ETHxToken.connect(staderOwner).deploy()

  console.log(' ethX deployed at ', ethxToken.address)

  //console.log("ethx is ", ethxToken.address);

  // const ETHDepositFactory = await ethers.getContractFactory('DepositContract')
  // const ethDeposit = await ETHDepositFactory.deploy()

  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT ?? ''

  const ETHDeposit = await ethers.getContractFactory('DepositContract')
  const ethDeposit = await ETHDeposit.attach(ethDepositContract)

  //console.log("ethDeposit is ", ethDeposit.address);

  const userWithdrawFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawManager = await upgrades.deployProxy(userWithdrawFactory, [staderOwner.address])
  console.log(' userWithdrawManager deployed at ', userWithdrawManager.address)

  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const staderStakingPoolManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethxToken.address,
    staderOracle.address,
    userWithdrawManager.address,
    [staderOwner.address, staderOwner.address],
    [staderOwner.address, staderOwner.address],
    staderOwner.address,
    10,
  ])

  console.log(' staderStakingPoolManager deployed at ', staderStakingPoolManager.address)

  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const socializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    staderOwner.address,
    staderStakingPoolManager.address,
    staderOwner.address,
  ])

  console.log(' socializingPoolContract deployed at ', socializingPoolContract.address)

  const vaultFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactoryInstance = await upgrades.deployProxy(vaultFactory, [
    staderOwner.address,
    staderOwner.address,
    staderOwner.address,
  ])

  console.log(' vaultFactoryInstance deployed at ', vaultFactoryInstance.address)

  const poolFactory = await ethers.getContractFactory('PoolFactory')
  const poolFactoryInstance = await upgrades.deployProxy(poolFactory, [staderOwner.address])

  const PermissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(PermissionedNodeRegistryFactory, [
    staderOwner.address,
    vaultFactoryInstance.address,
    socializingPoolContract.address,
  ])

  console.log(' permissionedNodeRegistry deployed at ', permissionedNodeRegistry.address)

  const PermissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(PermissionlessNodeRegistryFactory, [
    staderOwner.address,
    vaultFactoryInstance.address,
    socializingPoolContract.address,
    poolFactoryInstance.address,
  ])

  console.log(' permissionlessNodeRegistry deployed at ', permissionlessNodeRegistry.address)

  const staderPermissinedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const staderPermissionedPool = await upgrades.deployProxy(staderPermissinedPoolFactory, [
    staderOwner.address,
    permissionedNodeRegistry.address,
    ethDeposit.address,
    vaultFactoryInstance.address,
    staderStakingPoolManager.address,
  ])

  console.log(' staderPermissionedPool deployed at ', staderPermissionedPool.address)

  const staderPermissionLessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const staderPermissionLessPool = await upgrades.deployProxy(staderPermissionLessPoolFactory, [
    staderOwner.address,
    permissionlessNodeRegistry.address,
    ethDeposit.address,
    vaultFactoryInstance.address,
    staderStakingPoolManager.address,
  ])

  console.log(' staderPermissionLessPool deployed at ', staderPermissionLessPool.address)

  const staderPoolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelector = await upgrades.deployProxy(staderPoolSelectorFactory, [
    100,
    0,
    staderOwner.address,
    poolFactoryInstance.address,
  ])

  console.log(' poolSelector deployed at ', poolSelector.address)

  // Grant Role

  const poolFactoryAdmin = await poolFactoryInstance.POOL_FACTORY_ADMIN()

  await poolFactoryInstance.grantRole(poolFactoryAdmin, staderOwner.address)

  console.log('granted pool factory admin role to owner')

  const minterRole = await ethxToken.MINTER_ROLE()

  await ethxToken.grantRole(minterRole, staderStakingPoolManager.address)
  console.log('granted minter role to pool manager')

  const poolManager = await poolSelector.STADER_STAKE_POOL_MANAGER()
  await poolSelector.grantRole(poolManager, staderStakingPoolManager.address)
  console.log('granted pool manager role to stader pool manager')

  const permissionlessPool = await permissionlessNodeRegistry.PERMISSIONLESS_POOL()
  await permissionlessNodeRegistry.grantRole(permissionlessPool, staderPermissionLessPool.address)
  console.log('granted permissionlessPool role to permissionless contract')

  const permissionedPool = await permissionedNodeRegistry.PERMISSIONED_POOL_CONTRACT()
  await permissionedNodeRegistry.grantRole(permissionedPool, staderPermissionedPool.address)
  console.log('granted permissionedPool role to permissioned contract')

  const staderNetworkPool = await permissionedNodeRegistry.STADER_NETWORK_POOL()
  await permissionedNodeRegistry.grantRole(staderNetworkPool, staderPermissionedPool.address)
  await permissionlessNodeRegistry.grantRole(staderNetworkPool, staderPermissionLessPool.address)
  await vaultFactoryInstance.grantRole(staderNetworkPool, permissionlessNodeRegistry.address)
  await vaultFactoryInstance.grantRole(staderNetworkPool, permissionedNodeRegistry.address)
  console.log('granted stader network role to different contracts')

  const managerBot = await permissionedNodeRegistry.STADER_MANAGER_BOT()
  await permissionedNodeRegistry.grantRole(managerBot, staderOwner.address)
  await permissionlessNodeRegistry.grantRole(managerBot, staderOwner.address)
  console.log('granted manager bot role to owner')

  //Setter

  const addPool1Txn = await poolFactoryInstance
    .connect(staderOwner)
    .addNewPool('PERMISSIONLESS', staderPermissionLessPool.address)
  addPool1Txn.wait()

  console.log('permission less pool added')

  const addPool2Txn = await poolFactoryInstance
    .connect(staderOwner)
    .addNewPool('PERMISSIONED', staderPermissionedPool.address)
  addPool2Txn.wait()

  console.log('permissioned pool added')
}

main()
