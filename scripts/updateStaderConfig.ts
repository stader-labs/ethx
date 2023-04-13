import { ethers } from 'hardhat'

async function main() {
  const socializingCycleValue: any = process.env.SOCIALIZING_POOL_CYCLE_DURATION
  const socializingPoolOptInCoolDown: any = process.env.SOCIALIZING_POOL_OPT_IN_COOL_DOWN_PERIOD
  const rewardThreshold: any = process.env.REWARD_THRESHOLD
  const minBlockDelayToFinalizeRequest: any = process.env.MIN_BLOCK_DELAY_TO_FINALIZE_REQUEST
  const staderTreasury = process.env.STADER_TREASURY ?? ''
  const vaultFactory = process.env.VAULT_FACTORY ?? ''
  const auction = process.env.AUCTION ?? ''
  const ETHxToken = process.env.ETHx ?? ''
  const staderToken = process.env.SD_TOKEN ?? ''
  const penaltyContract = process.env.PENALTY ?? ''
  const permissionedNodeRegistry = process.env.PERMISSIONED_NODE_REGISTRY ?? ''
  const permissionedPool = process.env.PERMISSIONED_POOL ?? ''
  const permissionlessNodeRegistry = process.env.PERMISSIONLESS_NODE_REGISTRY ?? ''
  const permissionlessPool = process.env.PERMISSIONLESS_POOL ?? ''
  const poolSelector = process.env.POOL_SELECTOR ?? ''
  const poolUtils = process.env.POOL_UTILS ?? ''
  const sdCollateral = process.env.SD_COLLATERAL ?? ''
  const permissionedSocializingPool = process.env.PERMISSIONED_SOCIALIZING_POOL ?? ''
  const permissionlessSocializingPool = process.env.PERMISSIONLESS_SOCIALIZING_POOL ?? ''
  const staderConfig = process.env.STADER_CONFIG ?? ''
  const insuranceFund = process.env.STADER_INSURANCE_FUND ?? ''
  const staderOracle = process.env.STADER_ORACLE ?? ''
  const stakePoolManager = process.env.STAKE_POOL_MANAGER ?? ''
  const userWithdrawManager = process.env.USER_WITHDRAW_MANAGER ?? ''

  const staderConfigFactory = await ethers.getContractFactory('StaderConfig')
  const staderConfigInstance = await staderConfigFactory.attach(staderConfig)

  const updateSocializingCycleTx = await staderConfigInstance.updateSocializingPoolCycleDuration(socializingCycleValue)
  updateSocializingCycleTx.wait()

  const updateCoolDownPeriodTx = await staderConfigInstance.updateSocializingPoolOptInCoolingPeriod(
    socializingPoolOptInCoolDown
  )
  updateCoolDownPeriodTx.wait()

  const updateRewardThresholdTx = await staderConfigInstance.updateRewardsThreshold(rewardThreshold)
  updateRewardThresholdTx.wait()

  const updateFinalizationDelayTx = await staderConfigInstance.updateMinBlockDelayToFinalizeWithdrawRequest(
    minBlockDelayToFinalizeRequest
  )
  updateFinalizationDelayTx.wait()

  const updateTreasuryTx = await staderConfigInstance.updateStaderTreasury(staderTreasury)
  updateTreasuryTx.wait()

  const updateVaultTx = await staderConfigInstance.updateVaultFactory(vaultFactory)
  updateVaultTx.wait()

  const updateAuctionTx = await staderConfigInstance.updateAuctionContract(auction)
  updateAuctionTx.wait()

  const updateETHxTokenTx = await staderConfigInstance.updateETHxToken(ETHxToken)
  updateETHxTokenTx.wait()

  const updateStaderTokenTx = await staderConfigInstance.updateStaderToken(staderToken)
  updateStaderTokenTx.wait()

  const updatePenaltyTx = await staderConfigInstance.updatePenaltyContract(penaltyContract)
  updatePenaltyTx.wait()

  const updatePermissionedNodRegistryTx = await staderConfigInstance.updatePermissionedNodeRegistry(
    permissionedNodeRegistry
  )
  updatePermissionedNodRegistryTx.wait()

  const updatePermissionedPoolTx = await staderConfigInstance.updatePermissionedPool(permissionedPool)
  updatePermissionedPoolTx.wait()

  const updatePermissionlessNodeRegistryTx = await staderConfigInstance.updatePermissionlessNodeRegistry(
    permissionlessNodeRegistry
  )
  updatePermissionlessNodeRegistryTx.wait()

  const updatePermissionlessPoolTx = await staderConfigInstance.updatePermissionlessPool(permissionlessPool)
  updatePermissionlessPoolTx.wait()

  const updatePoolSelectorTx = await staderConfigInstance.updatePoolSelector(poolSelector)
  updatePoolSelectorTx.wait()

  const updatePoolUtilsTx = await staderConfigInstance.updatePoolUtils(poolUtils)
  updatePoolUtilsTx.wait()

  const updateSDCollateralTx = await staderConfigInstance.updateSDCollateral(sdCollateral)
  updateSDCollateralTx.wait()

  const updatePermissionedSocializeTx = await staderConfigInstance.updatePermissionedSocializingPool(
    permissionedSocializingPool
  )
  updatePermissionedSocializeTx.wait()

  const updatePermissionlessSocializingPoolTx = await staderConfigInstance.updatePermissionlessSocializingPool(
    permissionlessSocializingPool
  )
  updatePermissionlessSocializingPoolTx.wait()

  const updateInsuranceFundTx = await staderConfigInstance.updateStaderInsuranceFund(insuranceFund)
  updateInsuranceFundTx.wait()

  const updateStaderOracleTx = await staderConfigInstance.updateStaderOracle(staderOracle)
  updateStaderOracleTx.wait()

  const updatePoolManagerTx = await staderConfigInstance.updateStakePoolManager(stakePoolManager)
  updatePoolManagerTx.wait()

  const updateUserWithdrawManagerTx = await staderConfigInstance.updateUserWithdrawManager(userWithdrawManager)
  updateUserWithdrawManagerTx.wait()

  console.log('done')
}

main()
