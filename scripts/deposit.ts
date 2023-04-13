import { ethers } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const poolManager = process.env.STADER_STAKE_POOL_MANAGER ?? ''
  const poolManagerFactory = await ethers.getContractFactory('StaderStakePoolsManager')
  const poolManagerInstance = await poolManagerFactory.attach(poolManager)
  const depositTx = await poolManagerInstance.deposit(owner.address, { value: ethers.utils.parseEther('0.005') })
  depositTx.wait()
  console.log(`deposited ${ethers.utils.parseEther('0.005')} successfully`)
}

main()
