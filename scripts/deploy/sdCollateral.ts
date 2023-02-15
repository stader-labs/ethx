// weth-usdc pool : 0x09a29d678e9c7e150c43045e24a6ef974381a4f9
// weth-link pool : 0x465F4955303A07fa745e81C400a2D43092abd1Da
// link : 0xe9c4393a23246293a8D31BF7ab68c17d4CF90A29
// weth: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6
// usdc: 0x65aFADD39029741B3b8f0756952C74678c9cEC93
import { ethers, upgrades } from 'hardhat'
import { deployNonUpgradeableContract, deployUpgradeableContract } from '../utils'

async function main() {
  const twapContractAddr = await deployNonUpgradeableContract('TWAPGetter')

  const _sdERC20Addr = '0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6' // weth for now // required
  const _usdcERC20Addr = '0x65aFADD39029741B3b8f0756952C74678c9cEC93'
  const _wethERC20Addr = '0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6'
  const _sdUSDCPool = '0x09a29d678e9c7e150c43045e24a6ef974381a4f9' // wethUSDC for now // required
  const _wethUSDCPool = '0x09a29d678e9c7e150c43045e24a6ef974381a4f9'
  const priceFetcherAddr = await deployUpgradeableContract(
    'PriceFetcher',
    _sdERC20Addr,
    _usdcERC20Addr,
    _wethERC20Addr,
    _sdUSDCPool,
    _wethUSDCPool,
    twapContractAddr
  )

  // const [owner] = await ethers.getSigners()
  // const _xsdERC20Addr = '' // required
  // const _sdStakingContractAddr = '' // required
  // const sdCollateralAddr = await deployUpgradeableContract(
  //   'SDCollateral',
  //   owner.address,
  //   _sdERC20Addr,
  //   _xsdERC20Addr,
  //   priceFetcherAddr,
  //   _sdStakingContractAddr
  // )
}

main()

// TWAPGetter Contract deployed to: 0xA5e90041fB2cBc8022Ba7aBeEa1F237372766487
// Proxy PriceFetcher deployed to: 0x08Fbb9359F9919f38c23164686240A828199B0b0
// Impl PriceFetcher deployed to: 0x33006798401E4eB2bFB389F37416DB9B24bDf717

// 0x459E932816AD209C7327D565a4379C66671D0bA1 p1
// 0xC3424785c72477c9495AFC1bb80f95243A8150B8 p2
