import { ethers } from 'hardhat'

async function main() {
  const ratedV1Mock = await ethers.deployContract('RatedV1Mock', [])
  console.log('RatedV1Mock deployed to: ', ratedV1Mock.address)
}

main()
