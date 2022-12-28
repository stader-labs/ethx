const { ethers } = require('hardhat')
import { createStaderManagerInstance } from './createStaderManagerInstance'

async function main() {
  const stakingManagerInstance = await createStaderManagerInstance()
  const socializingPoolAddress = process.env.SOCIALIZING_POOL
  const staderOracle = process.env.ORACLE
  const [owner] = await ethers.getSigners()
  const setSocializingPoolAddressTxn = await stakingManagerInstance.updateSocializingPoolAddress(socializingPoolAddress)
  setSocializingPoolAddressTxn.wait()
  console.log('socializingPool Address updated')

  const setOracleTxn = await stakingManagerInstance.updateStaderOracle(staderOracle)
  setOracleTxn.wait()
  console.log('stader oracle address updated')
}

main()
