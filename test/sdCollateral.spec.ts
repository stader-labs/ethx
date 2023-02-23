import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ethers, upgrades } from 'hardhat'
import { SDCollateral } from '../typechain-types'

describe('SD/xSD as Collateral Contract', () => {
  let admin: SignerWithAddress
  let users: SignerWithAddress[]
  let _sdERC20Addr: string
  let _xsdERC20Addr: string
  let _priceFetcherAddr: string
  let _sdStakingContractAddr: string

  let sdCollateralContract: SDCollateral

  beforeEach(async () => {
    ;[admin, ...users] = await ethers.getSigners()

    _sdERC20Addr = _xsdERC20Addr = _priceFetcherAddr = _sdStakingContractAddr = admin.address

    sdCollateralContract = (await upgrades.deployProxy(await ethers.getContractFactory('SDCollateral'), [
      admin.address,
      _sdERC20Addr,
      _xsdERC20Addr,
      _priceFetcherAddr,
      _sdStakingContractAddr,
    ])) as SDCollateral
    await sdCollateralContract.deployed()
  })

  it('just a sample test', () => {
    expect(2).to.be.eq(2)
  })
})
