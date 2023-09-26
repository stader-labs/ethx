import { ethers } from 'hardhat'

async function main() {
  const poolManagerFactory = await ethers.getContractFactory('SSVValidatorWithdrawalVault')
  const poolManagerInstance = await poolManagerFactory.attach('0xfD376Eb205023e682Fb5B107c1f37A46e3dD4Cda')
  const depositTx = await poolManagerInstance.distributeRewards()
  depositTx.wait()
  console.log('distributed reward successfully')
}

main()
