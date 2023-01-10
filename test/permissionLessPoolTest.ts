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

describe('permission less pool tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  it('revert when node deposit is not 4 eth', async function () {
    expect(
      onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 2, '1')
    ).to.be.revertedWith('invalid collateral')
    expect(
      onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 2, '5')
    ).to.be.revertedWith('invalid collateral')
  })

  it('onboard permission and permission less validators', async function () {
    await onboardPermissionedValidator(env.staderManagedStakePool, adr.staderOwner.address, 0)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 1, '4')
    await onboardPermissionedValidator(env.staderManagedStakePool, adr.staderOwner.address, 2)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 3, '4')
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(4)
    expect(await env.operatorRegistry.operatorCount()).to.be.equal(2)
  })

  it('revert when registering same validator again', async function () {
    expect(
      onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 3, '4')
    ).to.be.revertedWith('validator already in use')
  })

  it('when more than 32 ETH have been staked', async () => {
    await env.staderStakingPoolManager
      .connect(adr.staker1)
      .deposit(adr.staker1.address, { value: ethers.utils.parseEther('20') })
    await env.staderStakingPoolManager
      .connect(adr.staker2)
      .deposit(adr.staker2.address, { value: ethers.utils.parseEther('10') })
    await env.staderStakingPoolManager
      .connect(adr.staker3)
      .deposit(adr.staker3.address, { value: ethers.utils.parseEther('10') })
    await env.staderStakingPoolManager
      .connect(adr.staker4)
      .deposit(adr.staker4.address, { value: ethers.utils.parseEther('10') })
    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('20') })
  })

  it('call select pool, 2 validator should get register via stader permission less pool', async () => {
    await env.staderStakingPoolManager.updatePoolWeights(100, 0)
    await env.staderStakingPoolManager.selectPool(0, 1)
    expect(await provider.getBalance(env.staderPermissionLessPool.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('14'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('64'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(2)
    const permissionLessOperatorIndex = await env.operatorRegistry.getOperatorIndexById(0)
    const permissionLessOperator = await env.operatorRegistry.operatorRegistry(permissionLessOperatorIndex)
    expect(permissionLessOperator.activeValidatorCount).to.be.equal(2)
  })

  it('revert if permission less pool balance less than 32 eth', async function () {
    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('14') })
    expect(env.staderStakingPoolManager.selectPool()).to.be.revertedWith('not enough balance to deposit')
  })

  it('revert if no new validator left to deposit', async function () {
    const tx = {
      to: env.staderPermissionLessPool.address,
      value: ethers.utils.parseEther('4'),
    }
    const transaction = await adr.staker1.sendTransaction(tx)
    expect(await provider.getBalance(env.staderPermissionLessPool.address)).to.be.equal(ethers.utils.parseEther('4'))
    expect(env.staderStakingPoolManager.selectPool()).to.be.revertedWith('permissionLess validator not available')
  })

  it('revert while updating withdraw credential', async () => {
    expect(
      env.staderPermissionLessPool.connect(adr.staker1).updateWithdrawCredential(env.staderManagedStakePool.address)
    ).to.be.reverted
  })

  it('revert while updating validator registry ', async () => {
    expect(
      env.staderPermissionLessPool
        .connect(adr.staker1)
        .updateStaderValidatorRegistry(env.staderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderPermissionLessPool.updateStaderValidatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating operator registry ', async () => {
    expect(
      env.staderPermissionLessPool.connect(adr.staker1).updateStaderOperatorRegistry(env.staderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderPermissionLessPool.updateStaderOperatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })
})
