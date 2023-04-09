import { ethers, upgrades } from 'hardhat'
import { deployNonUpgradeableContract, deployUpgradeableContract } from '../utils'

async function main() {
  const [manager] = await ethers.getSigners()
  const staderConfigAddr = '0xe34c84A15326f7980F59DE6b5A77C57ca2043c48'
  const duration = ethers.BigNumber.from('86400')
  const bidIncrement = ethers.utils.parseEther('0.001')
  const auctionContractAddr = await deployUpgradeableContract(
    'Auction',
    staderConfigAddr,
    manager.address,
    duration,
    bidIncrement
  )
}

main()
