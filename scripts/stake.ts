import { ethers } from 'hardhat'
import { createStaderManagerInstance } from './createStaderManagerInstance'

async function main() {
  const ssvManagerInstance = await createStaderManagerInstance()
  const [owner] = await ethers.getSigners()
  const staketxn = await ssvManagerInstance.deposit(owner.address, { value: ethers.utils.parseEther('29') })
  staketxn.wait()
  console.log('staked succesfully')
}
main()
