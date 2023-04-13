import { ethers, upgrades } from 'hardhat'

async function main() {
  const auction = process.env.AUCTION ?? ''
  const auctionFactory = await ethers.getContractFactory('Auction')
  const auctionInstance = await auctionFactory.attach(auction)

  const auctionUpgraded = await upgrades.upgradeProxy(auctionInstance, auctionFactory)

  console.log('auction proxy address ', auctionUpgraded.address)

  console.log('upgraded auction contract')
}

main()
