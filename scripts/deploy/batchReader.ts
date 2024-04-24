import { ethers } from 'hardhat'

async function main() {
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''

  const batchReader = await ethers.deployContract('BatchReader', [staderConfigAddr])
  console.log('BatchReader deployed to: ', batchReader.address)
}

main()
