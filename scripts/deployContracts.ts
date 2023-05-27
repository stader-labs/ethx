import { ethers, upgrades } from 'hardhat'

async function main() {
  console.log('starting deployment process...')
  const staderAdmin = process.env.STADER_ADMIN ?? ''
  const externalAdmin = process.env.EXTERNAL_ADMIN ?? ''
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT ?? ''
  const ratedOracle = process.env.RATED ?? ''

  const StaderConfig = await ethers.getContractFactory('StaderConfig')
  const staderConfig = await upgrades.deployProxy(StaderConfig, [staderAdmin, ethDepositContract])
  console.log('stader config deployed at ', staderConfig.address)

  const vaultFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactoryInstance = await upgrades.deployProxy(vaultFactory, [externalAdmin, staderConfig.address])
  console.log('vaultFactoryInstance deployed at ', vaultFactoryInstance.address)

  const auctionFactory = await ethers.getContractFactory('Auction')
  const auctionInstance = await upgrades.deployProxy(auctionFactory, [externalAdmin, staderConfig.address])
  console.log('auction contract deployed at ', auctionInstance.address)

  const ETHxFactory = await ethers.getContractFactory('ETHx')
  const ETHxToken = await upgrades.deployProxy(ETHxFactory, [externalAdmin, staderConfig.address])
  console.log('ETHx deployed at ', ETHxToken.address)

  const operatorRewardCollectorFactory = await ethers.getContractFactory('OperatorRewardsCollector')
  const operatorRewardCollector = await upgrades.deployProxy(operatorRewardCollectorFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('operator reward collector at ', operatorRewardCollector.address)

  const penaltyFactory = await ethers.getContractFactory('Penalty')
  const penaltyInstance = await upgrades.deployProxy(penaltyFactory, [externalAdmin, staderConfig.address, ratedOracle])
  console.log('penalty contract deployed at ', penaltyInstance.address)

  const PermissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(PermissionedNodeRegistryFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('permissionedNodeRegistry deployed at ', permissionedNodeRegistry.address)

  const permissinedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPool = await upgrades.deployProxy(permissinedPoolFactory, [externalAdmin, staderConfig.address])
  console.log('permissionedPool deployed at ', permissionedPool.address)

  const PermissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(PermissionlessNodeRegistryFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('permissionlessNodeRegistry deployed at ', permissionlessNodeRegistry.address)

  const permissionlessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const permissionlessPool = await upgrades.deployProxy(permissionlessPoolFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('permissionlessPool deployed at ', permissionlessPool.address)

  const poolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelector = await upgrades.deployProxy(poolSelectorFactory, [externalAdmin, staderConfig.address])
  console.log('poolSelector deployed at ', poolSelector.address)

  const poolUtilsFactory = await ethers.getContractFactory('PoolUtils')
  const poolUtilsInstance = await upgrades.deployProxy(poolUtilsFactory, [externalAdmin, staderConfig.address])
  console.log('poolUtils deployed at ', poolUtilsInstance.address)

  const SDCollateralFactory = await ethers.getContractFactory('SDCollateral')
  const SDCollateral = await upgrades.deployProxy(SDCollateralFactory, [externalAdmin, staderConfig.address])
  console.log('SDCollateral deployed at ', SDCollateral.address)

  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const permissionedSocializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('permissioned socializingPoolContract deployed at ', permissionedSocializingPoolContract.address)

  const permissionlessSocializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    externalAdmin,
    staderConfig.address,
  ])
  console.log('permissionless socializingPoolContract deployed at ', permissionlessSocializingPoolContract.address)

  const insuranceFundFactory = await ethers.getContractFactory('StaderInsuranceFund')
  const insuranceFund = await upgrades.deployProxy(insuranceFundFactory, [externalAdmin, staderConfig.address])
  console.log('insurance fund deployed at ', insuranceFund.address)

  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracle = await upgrades.deployProxy(staderOracleFactory, [externalAdmin, staderConfig.address])
  console.log('stader oracle deployed at ', staderOracle.address)

  const poolManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const staderStakingPoolManager = await upgrades.deployProxy(poolManagerFactory, [externalAdmin, staderConfig.address])
  console.log('staderStakingPoolManager deployed at ', staderStakingPoolManager.address)

  const userWithdrawFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawManager = await upgrades.deployProxy(userWithdrawFactory, [externalAdmin, staderConfig.address])
  console.log('userWithdrawManager deployed at ', userWithdrawManager.address)

  const NodeELRewardVault = await ethers.getContractFactory('NodeELRewardVault')
  const nodeELRewardVault = await NodeELRewardVault.deploy()
  await nodeELRewardVault.deployed()
  console.log('nodeELRewardVault ', nodeELRewardVault.address)

  const ValidatorWithdrawalVault = await ethers.getContractFactory('ValidatorWithdrawalVault')
  const validatorWithdrawalVault = await ValidatorWithdrawalVault.deploy()
  await validatorWithdrawalVault.deployed()
  console.log('validatorWithdrawalVault ', validatorWithdrawalVault.address)
}

main()
