import { ethers } from 'hardhat'

async function main() {
  const staderConfig = await ethers.getContractFactory('StaderConfig')
  const staderConfigInstance = await staderConfig.attach('')

  const updateSocializingCycleTx = await staderConfigInstance.updateSocializingPoolCycleDuration('')
  updateSocializingCycleTx.wait()

  const updateCoolDownPeriodTx = await staderConfigInstance.updateSocializingPoolOptInCoolingPeriod('')
  updateCoolDownPeriodTx.wait()

  const updateRewardThresholdTx = await staderConfigInstance.updateRewardsThreshold(ethers.utils.parseEther(''))
  updateRewardThresholdTx.wait()

  const updateFinalizationDelayTx = await staderConfigInstance.updateMinDelayToFinalizeWithdrawRequest('')
  updateFinalizationDelayTx.wait()

  const updateTreasuryTx = await staderConfigInstance.updateStaderTreasury('')
  updateTreasuryTx.wait()

  const updateVaultTx = await staderConfigInstance.updateVaultFactory('')
  updateVaultTx.wait()

  const updateAuctionTx = await staderConfigInstance.updateAuctionContract('')
  updateAuctionTx.wait()

  const updateETHxTokenTx = await staderConfigInstance.updateETHxToken('')
  updateETHxTokenTx.wait()

  const updateStaderTokenTx = await staderConfigInstance.updateStaderToken('')
  updateStaderTokenTx.wait()

  const updatePenaltyTx = await staderConfigInstance.updatePenaltyContract('')
  updatePenaltyTx.wait()

  const updatePermissionedNodRegistryTx = await staderConfigInstance.updatePermissionedNodeRegistry('')
  updatePermissionedNodRegistryTx.wait()

  const updatePermissionedPoolTx = await staderConfigInstance.updatePermissionedPool('')
  updatePermissionedPoolTx.wait()

  const updatePermissionlessNodeRegistryTx = await staderConfigInstance.updatePermissionlessNodeRegistry('')
  updatePermissionlessNodeRegistryTx.wait()

  const updatePermissionlessPoolTx = await staderConfigInstance.updatePermissionlessPool('')
  updatePermissionlessPoolTx.wait()

  const updatePoolSelectorTx = await staderConfigInstance.updatePoolSelector('')
  updatePoolSelectorTx.wait()

  const updatePoolUtilsTx = await staderConfigInstance.updatePoolUtils('')
  updatePoolUtilsTx.wait()

  const updateSDCollateralTx = await staderConfigInstance.updateSDCollateral('')
  updateSDCollateralTx.wait()

  const updatePermissionedSocializeTx = await staderConfigInstance.updatePermissionedSocializingPool('')
  updatePermissionedSocializeTx.wait()

  const updatePermissionlessSocializingPoolTx = await staderConfigInstance.updatePermissionlessSocializingPool('')
  updatePermissionlessSocializingPoolTx.wait()

  const updateInsuranceFundTx = await staderConfigInstance.updateStaderInsuranceFund('')
  updateInsuranceFundTx.wait()

  const updateStaderOracleTx = await staderConfigInstance.updateStaderOracle('')
  updateStaderOracleTx.wait()

  const updatePoolManagerTx = await staderConfigInstance.updateStakePoolManager('')
  updatePoolManagerTx.wait()

  const updateUserWithdrawManagerTx = await staderConfigInstance.updateUserWithdrawManager('')
  updateUserWithdrawManagerTx.wait()

  console.log('done')
}

main()
