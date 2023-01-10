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

describe('stader managed pool tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
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
    expect(onboardPermissionedValidator(env.staderManagedStakePool, adr.staderOwner.address, 2)).to.be.revertedWith(
      'validator already in use'
    )
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

  it('call select pool, 2 validator should get register via stader managed pool', async () => {
    await env.staderStakingPoolManager.selectPool(0, 1)
    expect(await provider.getBalance(env.staderManagedStakePool.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('6'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('64'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(2)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(2)
  })

  it('revert if no new validator available to deposit', async function () {
    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('30') })
    expect(env.staderStakingPoolManager.selectPool()).to.be.revertedWith('permissioned validator not available')
  })

  it('revert while updating withdraw credential', async () => {
    expect(env.staderManagedStakePool.connect(adr.staker1).updateWithdrawCredential(env.staderManagedStakePool.address))
      .to.be.reverted
  })

  it('revert while updating validator registry ', async () => {
    expect(
      env.staderManagedStakePool.connect(adr.staker1).updateStaderValidatorRegistry(env.staderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderManagedStakePool.updateStaderValidatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating operator registry ', async () => {
    expect(
      env.staderManagedStakePool.connect(adr.staker1).updateStaderOperatorRegistry(env.staderManagedStakePool.address)
    ).to.be.reverted
    expect(env.staderManagedStakePool.updateStaderOperatorRegistry(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })
})
