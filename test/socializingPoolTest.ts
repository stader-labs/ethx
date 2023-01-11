import '@nomicfoundation/hardhat-chai-matchers'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'

import { onboardPermissionedValidator } from './helper/validatorRegistrationStaderPool'
import { onboardPermissionLessValidator } from './helper/permissionlessValidator'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')

const provider = waffle.provider

let adr: any
let env: any

describe('socializing pool tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  it('onboard validators both permissioned and permissionLess', async function () {
    await onboardPermissionedValidator(env.staderManagedStakePool, adr.staker1.address, 0)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staker2.address, 1, '4')
    await onboardPermissionedValidator(env.staderManagedStakePool, adr.staker1.address, 2)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staker2.address, 3, '4')
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(4)
    expect(await env.operatorRegistry.operatorCount()).to.be.equal(2)
  })

  it('revert when distributeELRewardFee called by a user without REWARD_DISTRIBUTOR role', async function () {
    expect(env.socializePool.connect(adr.staker1).distributeELRewardFee()).to.be.reverted
  })

  it('revert when no EL rewards to distribute', async function () {
    expect(env.socializePool.connect(adr.staderOwner).distributeELRewardFee()).to.be.revertedWith(
      'not enough execution layer rewards'
    )
  })

  it('revert when no active validator on beacon chain', async function () {
    const poolManagerBalance = await provider.getBalance(env.staderStakingPoolManager.address)
    const tx = {
      to: env.socializePool.address,
      value: ethers.utils.parseEther('2'),
    }
    const transaction = await adr.staker1.sendTransaction(tx)
    expect(env.socializePool.connect(adr.staderOwner).distributeELRewardFee()).to.be.revertedWith(
      'No active validator on beacon chain'
    )
  })

  it('distributeELRewardFee when only one active permissioned validator', async function () {
    await env.staderStakingPoolManager
      .connect(adr.staker3)
      .deposit(adr.staker3.address, { value: ethers.utils.parseEther('32') })
    await env.staderStakingPoolManager.selectPool()
    const poolManagerBalance = await provider.getBalance(env.staderStakingPoolManager.address)

    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('32'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(1)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(1)

    await env.socializePool.connect(adr.staderOwner).distributeELRewardFee()
    expect(await env.ethxToken.balanceOf(adr.staderOwner.address)).to.be.equal(ethers.utils.parseEther('0.1'))
    expect(await env.ethxToken.balanceOf(permissionedOperator.operatorRewardAddress)).to.be.equal(
      ethers.utils.parseEther('0.1')
    )

    expect(
      Number(await provider.getBalance(env.staderStakingPoolManager.address)) - Number(poolManagerBalance)
    ).to.be.equal(Number(ethers.utils.parseEther('2')))
    expect(await provider.getBalance(env.socializePool.address)).to.be.equal(ethers.utils.parseEther('0'))
  })

  it('distributeELRewardFee when two active validator one each of permissioned and permission less', async function () {
    await env.staderStakingPoolManager.updatePoolWeights(100, 0)
    await env.staderStakingPoolManager
      .connect(adr.staker3)
      .deposit(adr.staker3.address, { value: ethers.utils.parseEther('28') })
    await env.staderStakingPoolManager.selectPool()
    const poolManagerBalance = await provider.getBalance(env.staderStakingPoolManager.address)

    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('64'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(2)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(1)

    const permissionLessOperatorIndex = await env.operatorRegistry.getOperatorIndexById(0)
    const permissionLessOperator = await env.operatorRegistry.operatorRegistry(permissionLessOperatorIndex)
    expect(permissionLessOperator.activeValidatorCount).to.be.equal(1)

    const tx = {
      to: env.socializePool.address,
      value: ethers.utils.parseEther('2'),
    }
    const transaction = await adr.staker1.sendTransaction(tx)

    await env.socializePool.connect(adr.staderOwner).distributeELRewardFee()
    expect(await env.ethxToken.balanceOf(adr.staderOwner.address)).to.be.equal(ethers.utils.parseEther('0.2'))
    expect(await env.ethxToken.balanceOf(permissionedOperator.operatorRewardAddress)).to.be.equal(
      ethers.utils.parseEther('0.15')
    )
    expect(await env.ethxToken.balanceOf(permissionLessOperator.operatorRewardAddress)).to.be.equal(
      ethers.utils.parseEther('0.05')
    )

    expect(
      Number(await provider.getBalance(env.staderStakingPoolManager.address)) - Number(poolManagerBalance)
    ).to.be.equal(Number(ethers.utils.parseEther('2')))
    expect(await provider.getBalance(env.socializePool.address)).to.be.equal(ethers.utils.parseEther('0'))
  })

  it('revert case while updating staderStakePoolManager', async function () {
    expect(env.socializePool.connect(adr.staker1).updateStaderStakePoolManager(env.staderStakingPoolManager.address)).to
      .be.reverted
    expect(env.socializePool.updateStaderStakePoolManager(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert case while updating staderTreasury', async function () {
    expect(env.socializePool.connect(adr.staker1).updateStaderTreasury(adr.staderOwner.address)).to.be.reverted
    expect(env.socializePool.updateStaderTreasury(adr.ZERO_ADDRESS)).to.be.revertedWith('Address cannot be zero')
  })

  it('revert case while updating staderValidatorRegistry', async function () {
    expect(env.socializePool.connect(adr.staker1).updateStaderValidatorRegistry(adr.staderOwner.address)).to.be.reverted
    expect(env.socializePool.updateStaderValidatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert case while updating staderOperatorRegistry', async function () {
    expect(env.socializePool.connect(adr.staker1).updateStaderOperatorRegistry(adr.staderOwner.address)).to.be.reverted
    expect(env.socializePool.updateStaderOperatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert case while updating fee Percentage', async function () {
    expect(env.socializePool.connect(adr.staker1).updateFeePercentage(20)).to.be.reverted
  })
})
