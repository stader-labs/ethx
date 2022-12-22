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
  const SSVRegistry = await ethers.getContractFactory('SSVRegistryMock')

  const ssvRegistry = await SSVRegistry.connect(ssvOwner).deploy()

  //console.log("ssv registry is ", ssvRegistry.address);

  const SSVToken = await ethers.getContractFactory('SSVTokenMock')

  const ssvToken = await SSVToken.connect(ssvOwner).deploy()
  //console.log("ssv token is ", ssvToken.address);

  const SSVNetwork = await ethers.getContractFactory('SSVNetworkMock')

  const ssvNetwork = await upgrades.deployProxy(SSVNetwork, [ssvRegistry.address, ssvToken.address, 0, 1000, 0, 0])

  //console.log("ssv network is ", ssvNetwork.address);

  const ETHxToken = await ethers.getContractFactory('ETHxVault')

  const ethxToken = await ETHxToken.connect(staderOwner).deploy()

  //console.log("ethx is ", ethxToken.address);

  const ETHDeposit = await ethers.getContractFactory('DepositContract')
  const ethDeposit = await ETHDeposit.deploy()

  //console.log("ethDeposit is ", ethDeposit.address);

  const validatorRegistryFactory = await ethers.getContractFactory('StaderValidatorRegistry')
  const validatorRegistry = await upgrades.deployProxy(validatorRegistryFactory)

  //console.log("validatorRegistry is ", validatorRegistry.address);

  const StaderManagedPoolFactory = await ethers.getContractFactory('StaderManagedStakePool')
  const StaderManagedStakePool = await upgrades.deployProxy(StaderManagedPoolFactory, [
    ethDeposit.address,
    '0x' + deposit.withdrawal_credentials,
    validatorRegistry.address,
    staderOwner.address,
  ])

  //console.log('StaderManagedStakePool is ', StaderManagedStakePool.address)

  const StaderSSVStakePoolFactory = await ethers.getContractFactory('StaderSSVStakePool')
  const staderSSVPool = await upgrades.deployProxy(StaderSSVStakePoolFactory, [
    ssvNetwork.address,
    ssvToken.address,
    ethDeposit.address,
    validatorRegistry.address,
    staderOwner.address,
  ])

  //console.log('staderSSVPool is ', staderSSVPool.address)

  const stakingManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const staderStakingPoolManager = await upgrades.deployProxy(stakingManagerFactory, [
    ethxToken.address,
    staderSSVPool.address,
    StaderManagedStakePool.address,
    100,
    0,
    10,
    [staderOwner.address, staderOwner.address],
    [staderOwner.address, staderOwner.address],
    staderOwner.address,
  ])

  //console.log("staderStakingPoolManager is ", staderStakingPoolManager.address);

  const ELRewardFactory = await ethers.getContractFactory('ExecutionLayerRewardContract')
  const ELRewardContract = await upgrades.deployProxy(ELRewardFactory, [
    staderStakingPoolManager.address,
    staderOwner.address,
  ])

  //console.log("ELRewardContract is ", ELRewardContract.address);

  const staderNetworkPool = await validatorRegistry.STADER_NETWORK_POOL()

  //console.log('staderNetwork Pool ', staderNetworkPool);
  //  await validatorRegistry.grantRole(staderNetworkPool, StaderManagedStakePool.address);
  //  await validatorRegistry.grantRole(staderNetworkPool, staderSSVPool.address);

  //console.log('granted network pool access');

  const setELRewardTxn = await staderStakingPoolManager
    .connect(staderOwner)
    .updateELRewardContract(ELRewardContract.address)
  setELRewardTxn.wait()
  //console.log("EL Rewards Address updated");

  const setValidatorRegistryTxn = await staderStakingPoolManager
    .connect(staderOwner)
    .updateStaderValidatorRegistry(validatorRegistry.address)
  setValidatorRegistryTxn.wait()
  //console.log("validator registry updated");

  const setStaderTreasuryTxn = await staderStakingPoolManager
    .connect(staderOwner)
    .updateStaderTreasury(staderOwner.address)
  setStaderTreasuryTxn.wait()
  //  console.log("stader treasury updated");

  await ssvNetwork.registerOperator(
    'Test0',
    '0xa4a569fb7fdf1db070c9eade52877ed35c50f49ef1cc36733dffc429ccb8858605251e4d45a6688380ab8f73d6584136',
    10000000000
  )
  await ssvNetwork.activ
  await ssvNetwork.registerOperator(
    'Test1',
    '0x8cc7ca706fffad15019c82a659f59a7615fa5f1dc0229f8d9b0e00b9df87cb1b823316e99ad2ffc8db5a34e495e1d95c',
    10000000000
  )
  await ssvNetwork.registerOperator(
    'Test2',
    '0x8c0bd85f5a975fa891577f1b09e84848e2ea9cd2e50bb91bcfbe99f14ae1030fa11317ca542733697678403009f668c2',
    10000000000
  )
  await ssvNetwork.registerOperator(
    'Test3',
    '0x90abf144f599bf8a496c8ec1d808262b2b864176b893b234a0cb4eb376f45aa4d691058977f07ab597bdfa5e34f27671',
    10000000000
  )

  const minterRole = await ethxToken.MINTER_ROLE()

  await ethxToken.connect(staderOwner).grantRole(minterRole, staderStakingPoolManager.address)

  await ssvToken.transfer(staderSSVPool.address, ethers.utils.parseEther('100'))
  await ssvToken.transfer(staderOwner.address, ethers.utils.parseEther('100'))

  return {
    ssvRegistry,
    ssvNetwork,
    ssvToken,
    ethDeposit,
    ethxToken,
    validatorRegistry,
    StaderManagedStakePool,
    staderSSVPool,
    staderStakingPoolManager,
    ELRewardContract,
  }
}

module.exports = {
  setupAddresses,
  setupEnvironment,
}
