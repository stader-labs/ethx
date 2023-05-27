const hre = require('hardhat')

// Array of contract addresses to be verified

const vaultFactory = process.env.VAULT_FACTORY ?? ''
const auction = process.env.AUCTION ?? ''
const ETHxToken = process.env.ETHx ?? ''
const staderToken = process.env.SD_TOKEN ?? ''
const operatorRewardCollector = process.env.OPERATOR_REWARD_COLLECTOR ?? ''
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
const nodeELRewardVault = process.env.NODE_EL_REWARD_VAULT_IMPL ?? ''
const withdrawVaultImpl = process.env.WITHDRAW_VAULT_IMPL ?? ''

const contractAddresses = [
  vaultFactory,
  auction,
  ETHxToken,
  operatorRewardCollector,
  penaltyContract,
  permissionedNodeRegistry,
  permissionedPool,
  permissionlessNodeRegistry,
  permissionlessPool,
  poolSelector,
  poolUtils,
  sdCollateral,
  permissionedSocializingPool,
  permissionlessSocializingPool,
  staderConfig,
  insuranceFund,
  staderOracle,
  stakePoolManager,
  userWithdrawManager,
  nodeELRewardVault,
  withdrawVaultImpl,
]

async function main() {
  // Loop through all contract addresses and verify them
  for (const contractAddress of contractAddresses) {
    try {
      // Run the hardhat verify task for the current contract address
      await hre.run('verify:verify', {
        address: contractAddress,
      })

      console.log(`Contract at address ${contractAddress} verified successfully!`)
    } catch (error) {
      console.error(`Failed to verify contract at address ${contractAddress}.`)
      console.error(error)
    }
  }
}

// Call the main function to start verifying contracts
main()
