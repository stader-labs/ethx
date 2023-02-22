import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()

  const poolFactoryContract = await deployPoolFactory()
  const vaultContract = await deployVault(owner)
  const ethXContract = await deployEthX()
  const oracleContract = await deployOracle()
  const poolManagerContract = await deployPoolManager(owner, ethXContract, oracleContract)
  const permissionedNodeRegistry = await deployPermissionedNodeRegistry(owner, vaultContract, oracleContract)
  const permissionedPool = await deployPermissionedPool(
    owner,
    permissionedNodeRegistry,
    vaultContract,
    vaultContract,
    poolFactoryContract
  )
  const permissionlessNodeRegistry = await deployPermissionlessNodeRegistry(
    owner,
    vaultContract,
    oracleContract,
    poolManagerContract
  )
  const permissionlessPool = await deployPermissionlessPool(
    owner,
    permissionlessNodeRegistry,
    vaultContract,
    vaultContract,
    poolFactoryContract
  )
}

async function deployVault(owner: any) {
  const rewardContractFactory = await ethers.getContractFactory('VaultFactory')
  const rewardFactoryInstance = await upgrades.deployProxy(rewardContractFactory, [
    owner.address,
    owner.address,
    owner.address,
  ])

  await rewardFactoryInstance.deployed()
  console.log('reward Factory deployed to:', rewardFactoryInstance.address)

  return rewardFactoryInstance
}

async function deployEthX() {
  const ethXFactory = await ethers.getContractFactory('ETHX')
  const ethX = await ethXFactory.deploy()
  await ethX.deployed()
  console.log('ethX Token deployed to:', ethX.address)

  return ethX
}

async function deployOracle() {
  const oracleFactory = await ethers.getContractFactory('StaderOracle')
  const oracle = await oracleFactory.deploy()
  await oracle.deployed()
  console.log('Oracle deployed to:', oracle.address)

  return oracle
}

async function deployPoolManager(owner: any, ethX: any, oracle: any) {
  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const stakingManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethX.address,
    oracle.address,
    owner.address,
    [owner.address, owner.address],
    [owner.address, owner.address],
    owner.address,
    10,
  ])

  await stakingManager.deployed()
  console.log('Stader Stake Pools Manager deployed to:', stakingManager.address)

  return stakingManager
}

async function deployPermissionedPool(
  owner: any,
  nodeRegistry: any,
  depositContract: any,
  vaultFactory: any,
  poolManager: any
) {
  const staderPermissinedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const staderPermissionedPool = await upgrades.deployProxy(staderPermissinedPoolFactory, [
    owner.address,
    nodeRegistry.address,
    depositContract.address,
    vaultFactory.address,
    poolManager.address,
  ])
  await staderPermissionedPool.deployed()
  console.log('Stader permissioned Pool deployed to:', staderPermissionedPool.address)

  return staderPermissionedPool
}

async function deployPermissionedNodeRegistry(owner: any, vaultFactory: any, socializePool: any) {
  const PermissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(PermissionedNodeRegistryFactory, [
    owner.address,
    vaultFactory.address,
    socializePool.address,
  ])

  await permissionedNodeRegistry.deployed()
  console.log('permissioned Node Registry deployed to:', permissionedNodeRegistry.address)

  return permissionedNodeRegistry
}

async function deployPermissionlessPool(
  owner: any,
  nodeRegistry: any,
  depositContract: any,
  vaultFactory: any,
  poolManager: any
) {
  const staderPermissinlessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const staderPermissionlessPool = await upgrades.deployProxy(staderPermissinlessPoolFactory, [
    owner.address,
    nodeRegistry.address,
    depositContract.address,
    vaultFactory.address,
    poolManager.address,
  ])
  await staderPermissionlessPool.deployed()
  console.log('Stader permissionless Pool deployed to:', staderPermissionlessPool.address)

  return staderPermissionlessPool
}

async function deployPermissionlessNodeRegistry(owner: any, vaultFactory: any, socializePool: any, poolFactory: any) {
  const PermissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(PermissionlessNodeRegistryFactory, [
    owner.address,
    owner.address,
    vaultFactory.address,
    socializePool.address,
    poolFactory.address,
  ])

  await permissionlessNodeRegistry.deployed()
  console.log('permissionless Node Registry deployed to:', permissionlessNodeRegistry.address)

  return permissionlessNodeRegistry
}

async function deployPoolFactory() {
  const poolFactory = await ethers.getContractFactory('PoolFactory')
  const poolFactoryInstance = await upgrades.deployProxy(poolFactory)
  await poolFactoryInstance.deployed()
  console.log('PoolFactory deployed to:', poolFactoryInstance.address)

  return poolFactoryInstance
}

main()
