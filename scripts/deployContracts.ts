import { ethers, upgrades } from 'hardhat'

async function main() {
  console.log('starting deployment process...')
  const admin = process.env.ADMIN ?? ''
  const ethDepositContract = process.env.ETH_DEPOSIT_CONTRACT ?? ''
  const permissionlessPoolWeight: any = process.env.PERMISSIONLESS_POOL_WEIGHT
  const permissionedPoolWeight: any = process.env.PERMISSIONED_POOL_WEIGHT

  const ratedOracle = process.env.RATED_ORACLE ?? ''

  const StaderConfig = await ethers.getContractFactory('StaderConfig')
  const staderConfig = await upgrades.deployProxy(StaderConfig, [admin, ethDepositContract])
  console.log('stader config deployed at ', staderConfig.address)

  const vaultFactory = await ethers.getContractFactory('VaultFactory')
  const vaultFactoryInstance = await upgrades.deployProxy(vaultFactory, [admin, staderConfig.address])
  console.log('vaultFactoryInstance deployed at ', vaultFactoryInstance.address)

  const auctionFactory = await ethers.getContractFactory('Auction')
  const auctionInstance = await upgrades.deployProxy(auctionFactory, [
    admin,
    staderConfig.address,
    ethers.BigNumber.from('86400'),
    ethers.utils.parseEther('0.001'),
  ])
  console.log('auction contract deployed at ', auctionInstance.address)

  const ETHxFactory = await ethers.getContractFactory('ETHx')
  const ETHxToken = await upgrades.deployProxy(ETHxFactory, [admin, staderConfig.address])
  console.log('ETHx deployed at ', ETHxToken.address)

  const penaltyFactory = await ethers.getContractFactory('Penalty')
  const penaltyInstance = await upgrades.deployProxy(penaltyFactory, [admin, staderConfig.address, ratedOracle])
  console.log('penalty contract deployed at ', penaltyInstance.address)

  const PermissionedNodeRegistryFactory = await ethers.getContractFactory('PermissionedNodeRegistry')
  const permissionedNodeRegistry = await upgrades.deployProxy(PermissionedNodeRegistryFactory, [
    admin,
    staderConfig.address,
  ])
  console.log('permissionedNodeRegistry deployed at ', permissionedNodeRegistry.address)

  const permissinedPoolFactory = await ethers.getContractFactory('PermissionedPool')
  const permissionedPool = await upgrades.deployProxy(permissinedPoolFactory, [admin, staderConfig.address])
  console.log('permissionedPool deployed at ', permissionedPool.address)

  const PermissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
  const permissionlessNodeRegistry = await upgrades.deployProxy(PermissionlessNodeRegistryFactory, [
    admin,
    staderConfig.address,
  ])
  console.log('permissionlessNodeRegistry deployed at ', permissionlessNodeRegistry.address)

  const permissionlessPoolFactory = await ethers.getContractFactory('PermissionlessPool')
  const permissionlessPool = await upgrades.deployProxy(permissionlessPoolFactory, [admin, staderConfig.address])
  console.log('permissionlessPool deployed at ', permissionlessPool.address)

  const poolSelectorFactory = await ethers.getContractFactory('PoolSelector')
  const poolSelector = await upgrades.deployProxy(poolSelectorFactory, [
    admin,
    staderConfig.address,
    permissionlessPoolWeight,
    permissionedPoolWeight,
  ])
  console.log('poolSelector deployed at ', poolSelector.address)

  const poolUtilsFactory = await ethers.getContractFactory('PoolUtils')
  const poolUtilsInstance = await upgrades.deployProxy(poolUtilsFactory, [admin, staderConfig.address])
  console.log('poolUtils deployed at ', poolUtilsInstance.address)

  const SDCollateralFactory = await ethers.getContractFactory('SDCollateral')
  const SDCollateral = await upgrades.deployProxy(SDCollateralFactory, [admin, staderConfig.address])
  console.log('SDCollateral deployed at ', SDCollateral.address)

  const socializingPoolFactory = await ethers.getContractFactory('SocializingPool')
  const permissionedSocializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    admin,
    staderConfig.address,
  ])
  console.log('permissioned socializingPoolContract deployed at ', permissionedSocializingPoolContract.address)

  const permissionlessSocializingPoolContract = await upgrades.deployProxy(socializingPoolFactory, [
    admin,
    staderConfig.address,
  ])
  console.log('permissionless socializingPoolContract deployed at ', permissionlessSocializingPoolContract.address)

  const insuranceFundFactory = await ethers.getContractFactory('StaderInsuranceFund')
  const insuranceFund = await upgrades.deployProxy(insuranceFundFactory, [admin, staderConfig.address])
  console.log('insurance fund deployed at ', insuranceFund.address)

  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracle = await upgrades.deployProxy(staderOracleFactory, [admin, staderConfig.address])
  console.log('stader oracle deployed at ', staderOracle.address)

  const poolManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const staderStakingPoolManager = await upgrades.deployProxy(poolManagerFactory, [admin, staderConfig.address])
  console.log('staderStakingPoolManager deployed at ', staderStakingPoolManager.address)

  const userWithdrawFactory = await ethers.getContractFactory('UserWithdrawalManager')
  const userWithdrawManager = await upgrades.deployProxy(userWithdrawFactory, [admin, staderConfig.address])
  console.log('userWithdrawManager deployed at ', userWithdrawManager.address)

  // Grant Role
  // const minterRole = await ETHxToken.MINTER_ROLE()
  // await ETHxToken.grantRole(minterRole, staderStakingPoolManager.address)
  // console.log('granted minter role to pool manager')

  // const burnerRole = await ETHxToken.BURNER_ROLE()
  // await ETHxToken.grantRole(burnerRole, userWithdrawManager.address)
  // console.log('granted burner role to user withdraw manager')

  // const nodeRegistryContract = await vaultFactoryInstance.NODE_REGISTRY_CONTRACT()
  // await vaultFactoryInstance.grantRole(nodeRegistryContract, permissionlessNodeRegistry.address)
  // await vaultFactoryInstance.grantRole(nodeRegistryContract, permissionedNodeRegistry.address)
  // console.log('granted node registry role to permissioned and permissionless node registries')

  // const managerRole = await staderConfig.MANAGER()
  // await staderConfig.grantRole(managerRole, manager)
  // console.log(`granted manager role to ${manager}`)

  // const operatorRole = await staderConfig.OPERATOR()
  // await staderConfig.grantRole(operatorRole, operator.address)
  // console.log(`granted operator role to ${operator.address}`)

  //update stader config admin at the last so we can update all contract address with stader internal admin

  //Setter

  // const addPool1Txn = await poolUtilsInstance
  //   .connect(operator.address)
  //   .addNewPool(permissionlessPoolId, permissionlessPool.address)
  // addPool1Txn.wait()
  // console.log('permission less pool added')

  // const addPool2Txn = await poolUtilsInstance.connect(operator.address).addNewPool(permissionedPoolId, permissionedPool.address)
  // addPool2Txn.wait()
  // console.log('permissioned pool added')
}

main()
