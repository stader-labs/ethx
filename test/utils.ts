/* eslint-disable no-undef */
/* eslint-disable arrow-body-style */
/* eslint-disable no-await-in-loop */
import deposit from '../scripts/deposits/deposit0.json'
import { ethers, upgrades } from 'hardhat'

const setupAddresses = async () => {
  const [staderOwner, ssvOwner, staker1, staker2, staker3, staker4, staker5] = await ethers.getSigners()

  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

  return {
    staderOwner,
    ssvOwner,
    staker1,
    staker2,
    staker3,
    staker4,
    staker5,
    ZERO_ADDRESS,
  }
}

const setupEnvironment = async (staderOwner: any, ssvOwner: any) => {
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracle = await upgrades.deployProxy(staderOracleFactory)

  const ETHxToken = await ethers.getContractFactory('ETHX')
  const ethxToken = await ETHxToken.connect(staderOwner).deploy()

  //console.log("ethx is ", ethxToken.address);

  const ETHDeposit = await ethers.getContractFactory('DepositContract')
  const ethDeposit = await ETHDeposit.deploy()

  //console.log("ethDeposit is ", ethDeposit.address);

  const operatorRegistryFactory = await ethers.getContractFactory('StaderOperatorRegistry')
  const operatorRegistry = await upgrades.deployProxy(operatorRegistryFactory)

  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistry = await upgrades.deployProxy(validatorRegistryFactory)

  //console.log("validatorRegistry is ", validatorRegistry.address);

  const staderPermissionedStakePoolFactory = await ethers.getContractFactory('StaderPermissionedStakePool')
  const staderPermissionedStakePool = await upgrades.deployProxy(staderPermissionedStakePoolFactory, [
    '0x' + deposit.withdrawal_credentials,
    ethDeposit.address,
    operatorRegistry.address,
    validatorRegistry.address,
    staderOwner.address,
  ])
  console.log('staderPermissionedStakePool is ', staderPermissionedStakePool.address)

  const staderPermissionLessPoolFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const staderPermissionLessPool = await upgrades.deployProxy(staderPermissionLessPoolFactory, [
    '0x' + deposit.withdrawal_credentials,
    ethDeposit.address,
    operatorRegistry.address,
    validatorRegistry.address,
    staderOwner.address,
  ])

  const permissionLessOperator = await staderPermissionLessPool.PERMISSION_LESS_OPERATOR()
  await staderPermissionLessPool.grantRole(permissionLessOperator, staderOwner.address)

  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const staderStakingPoolManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethxToken.address,
    staderPermissionLessPool.address,
    staderPermissionedStakePool.address,
    0,
    100,
    10,
    [staderOwner.address, staderOwner.address],
    [staderOwner.address, staderOwner.address],
    staderOwner.address,
  ])

  //console.log("staderStakingPoolManager is ", staderStakingPoolManager.address);

  // const poolManagerRole = await staderManagedStakePool.STADER_POOL_MANAGER()
  // await staderManagedStakePool.grantRole(poolManagerRole, staderStakingPoolManager.address)

  // const poolManagerRolePermissionLessPool = await staderPermissionLessPool.STADER_POOL_MANAGER()
  // await staderPermissionLessPool.grantRole(poolManagerRolePermissionLessPool, staderStakingPoolManager.address)

  const socializePoolFactory = await ethers.getContractFactory('SocializingPoolContract')
  const socializePool = await upgrades.deployProxy(socializePoolFactory, [
    operatorRegistry.address,
    validatorRegistry.address,
    staderStakingPoolManager.address,
    staderOwner.address,
    staderOwner.address,
  ])

  //console.log("ELRewardContract is ", ELRewardContract.address);

  const rewardDistributor = await socializePool.REWARD_DISTRIBUTOR()
  await socializePool.grantRole(rewardDistributor, staderOwner.address)

  const staderNetworkPool = await validatorRegistry.STADER_NETWORK_POOL()

  await validatorRegistry.grantRole(staderNetworkPool, staderPermissionedStakePool.address)
  await validatorRegistry.grantRole(staderNetworkPool, staderPermissionLessPool.address)

  console.log('granted network pool access to validator registry')

  const staderNetworkPoolOperatorRegistry = await operatorRegistry.STADER_NETWORK_POOL()

  await operatorRegistry.grantRole(staderNetworkPoolOperatorRegistry, staderPermissionedStakePool.address)
  await operatorRegistry.grantRole(staderNetworkPoolOperatorRegistry, staderPermissionLessPool.address)

  console.log('granted network pool access to operator registry')

  const setELRewardTxn = await staderStakingPoolManager
    .connect(staderOwner)
    .updateSocializingPoolAddress(socializePool.address)
  setELRewardTxn.wait()
  //console.log("EL Rewards Address updated");

  const setOracleTxn = await staderStakingPoolManager.updateStaderOracle(staderOracle.address)
  setOracleTxn.wait()
  console.log('stader oracle address updated')

  const minterRole = await ethxToken.MINTER_ROLE()

  await ethxToken.connect(staderOwner).grantRole(minterRole, staderStakingPoolManager.address)

  return {
    ethDeposit,
    ethxToken,
    staderOracle,
    validatorRegistry,
    operatorRegistry,
    staderPermissionedStakePool,
    staderPermissionLessPool,
    staderStakingPoolManager,
    socializePool,
  }
}

module.exports = {
  setupAddresses,
  setupEnvironment,
}
