const { ethers } = require('hardhat')
import { createStaderManagerInstance } from './createStaderManagerInstance'

async function main() {
  const stakingManagerInstance = await createStaderManagerInstance()
  const ELRewardAddress = process.env.EL_REWARD_CONTRACT
  const validatorRegistry = process.env.VALIDATOR_REGISTRY
  const ethXFeed = process.env.ETHX_FEED
  const [owner] = await ethers.getSigners()
  const setELRewardTxn = await stakingManagerInstance.updateELRewardContract(ELRewardAddress)
  setELRewardTxn.wait()
  console.log('EL Rewards Address updated')

  const setValidatorRegistryTxn = await stakingManagerInstance.updateStaderValidatorRegistry(validatorRegistry)
  setValidatorRegistryTxn.wait()
  console.log('validator registry updated')

  const setETHXFeedTxn = await stakingManagerInstance.updateEthXFeed(ethXFeed)
  setETHXFeedTxn.wait()
  console.log('ethX feed updated')

  const setStaderTreasuryTxn = await stakingManagerInstance.updateStaderTreasury(owner.address)
  setStaderTreasuryTxn.wait()
  console.log('stader treasury updated')
}

main()
