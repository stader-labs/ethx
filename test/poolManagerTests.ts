import '@nomicfoundation/hardhat-chai-matchers'
import { parse } from 'dotenv'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')
const provider = waffle.provider

let adr: any
let env: any

describe('stader pool manager tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  it('stake eth with 1:1 exchange rate', async () => {
    await env.staderStakingPoolManager
      .connect(adr.staker1)
      .deposit(adr.staker1.address, { value: ethers.utils.parseEther('10') })
    await env.staderStakingPoolManager
      .connect(adr.staker2)
      .deposit(adr.staker2.address, { value: ethers.utils.parseEther('10') })

    expect(await env.ethxToken.balanceOf(adr.staker1.address)).to.be.equal(ethers.utils.parseEther('10'))
    expect(await env.ethxToken.balanceOf(adr.staker2.address)).to.be.equal(ethers.utils.parseEther('10'))
  })

  it('staked amount cross 32 eth, ssv pool selected', async () => {
    await env.staderStakingPoolManager
      .connect(adr.staker3)
      .deposit(adr.staker3.address, { value: ethers.utils.parseEther('12') })

    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.staderSSVPool.address)).to.be.equal(ethers.utils.parseEther('32'))
  })

  it('staked amount cross 32 eth, ssv pool selected', async () => {
    await env.staderStakingPoolManager.updatePoolWeights(0, 100)
    await env.staderStakingPoolManager
      .connect(adr.staker4)
      .deposit(adr.staker4.address, { value: ethers.utils.parseEther('12') })

    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('20') })

    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.StaderManagedStakePool.address)).to.be.equal(ethers.utils.parseEther('32'))
  })

  it('revert while updating pool weights', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updatePoolWeights(50, 50)).to.be.reverted
    expect(env.staderStakingPoolManager.updatePoolWeights(80, 50)).to.be.revertedWith('Invalid weights')
  })

  it('revert while updating ssv pool address', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateSSVStakePoolAddresses(env.staderSSVPool.address)).to
      .be.reverted
    expect(env.staderStakingPoolManager.updateSSVStakePoolAddresses(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating stader pool address', async () => {
    expect(
      env.staderStakingPoolManager
        .connect(adr.staker1)
        .updateStaderStakePoolAddresses(env.StaderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderStakingPoolManager.updateStaderStakePoolAddresses(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating min deposit', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateMinDeposit(1)).to.be.reverted
    expect(env.staderStakingPoolManager.updateMinDeposit(0)).to.be.revertedWith('invalid minDeposit value')
  })

  it('revert while updating max deposit', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateMaxDeposit(50)).to.be.reverted
    expect(env.staderStakingPoolManager.updateMaxDeposit(0.5)).to.be.revertedWith('invalid maxDeposit value')
  })

  it('revert while updating ethX feed', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateEthXFeed(env.StaderManagedStakePool.address)).to.be
      .reverted
    expect(env.staderStakingPoolManager.updateEthXFeed(adr.ZERO_ADDRESS)).to.be.revertedWith('Address cannot be zero')
  })

  it('revert while updating ethX address', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateEthXAddress(env.StaderManagedStakePool.address)).to
      .be.reverted
    expect(env.staderStakingPoolManager.updateEthXAddress(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating EL reward contract address', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateELRewardContract(env.StaderManagedStakePool.address))
      .to.be.reverted
    expect(env.staderStakingPoolManager.updateELRewardContract(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating stader treasury address', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateStaderTreasury(env.StaderManagedStakePool.address))
      .to.be.reverted
    expect(env.staderStakingPoolManager.updateStaderTreasury(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating stader validator registry', async () => {
    expect(
      env.staderStakingPoolManager
        .connect(adr.staker1)
        .updateStaderValidatorRegistry(env.StaderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderStakingPoolManager.updateStaderValidatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })
})
