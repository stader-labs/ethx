import { ethers, upgrades } from 'hardhat'

async function main() {
  const [owner] = await ethers.getSigners()
  const staderConfigAddr = process.env.STADER_CONFIG ?? ''
  const auctionFactory = await ethers.getContractFactory('Auction')
  const duration = ethers.BigNumber.from('86400')
  const bidIncrement = ethers.utils.parseEther('0.001')
  const auctionContract = await upgrades.deployProxy(auctionFactory, [
    owner.address,
    staderConfigAddr,
    duration,
    bidIncrement,
  ])

  console.log('auction contract deployed at: ', auctionContract.address)
}

main()
