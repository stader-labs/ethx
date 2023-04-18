import { ethers } from 'hardhat'

async function main() {

    const withdrawVaultFactory = await ethers.getContractFactory('ValidatorWithdrawalVault')
  const withdrawVaultInstance = await withdrawVaultFactory.attach(
    '0xc9bF5b40E532E80B2F3a4dd13Ee79a6111Eb3468'
  )
  const settleFundTx = await withdrawVaultInstance.settleFunds()

  console.log('settled funds')

}
main()
