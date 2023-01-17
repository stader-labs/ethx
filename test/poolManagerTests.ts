import '@nomicfoundation/hardhat-chai-matchers'
import { parse } from 'dotenv'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')
import { onboardPermissionedValidator } from './helper/validatorRegistrationStaderPool'
import { onboardPermissionLessValidator } from './helper/permissionlessValidator'

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

  it('onboard validators both permissioned and permissionLess', async function () {
    await onboardPermissionedValidator(env.staderPermissionedStakePool, adr.staderOwner.address, 0)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 1, '4')
    await onboardPermissionedValidator(env.staderPermissionedStakePool, adr.staderOwner.address, 2)
    await onboardPermissionLessValidator(env.staderPermissionLessPool, adr.staderOwner.address, 3, '4')
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(4)
    expect(await env.operatorRegistry.operatorCount()).to.be.equal(2)
  })

  it('operator registry checks', async function () {
    const permissionLessOperatorIndex = await env.operatorRegistry.getOperatorIndexById(0)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionLessOperator = await env.operatorRegistry.operatorRegistry(permissionLessOperatorIndex)
    expect(permissionLessOperator.validatorCount).to.be.equal(2)
    expect(permissionLessOperator.activeValidatorCount).to.be.equal(0)

    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.validatorCount).to.be.equal(2)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(0)
  })

  it('staked amount cross 32 eth, call selectPool, permissioned pool selected', async () => {
    await env.staderStakingPoolManager
      .connect(adr.staker3)
      .deposit(adr.staker3.address, { value: ethers.utils.parseEther('12') })
    await env.staderStakingPoolManager.selectPool()
    expect(await provider.getBalance(env.staderPermissionedStakePool.address)).to.be.equal(
      ethers.utils.parseEther('32')
    )
    await env.staderPermissionedStakePool.depositEthToDepositContract()
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.staderPermissionedStakePool.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('32'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(1)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(1)
  })

  it('change pool weight, staked amount cross 28 eth, permission less pool selected', async () => {
    await env.staderStakingPoolManager.updatePoolWeights(100, 0)
    await env.staderStakingPoolManager
      .connect(adr.staker4)
      .deposit(adr.staker4.address, { value: ethers.utils.parseEther('12') })

    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('16') })
    await env.staderStakingPoolManager.selectPool()
    expect(await provider.getBalance(env.staderPermissionLessPool.address)).to.be.equal(ethers.utils.parseEther('36'))
    await env.staderPermissionLessPool.depositEthToDepositContract()
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.staderPermissionLessPool.address)).to.be.equal(ethers.utils.parseEther('4'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('64'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(2)
    const permissionLessOperatorIndex = await env.operatorRegistry.getOperatorIndexById(0)
    const permissionLessOperator = await env.operatorRegistry.operatorRegistry(permissionLessOperatorIndex)
    expect(permissionLessOperator.activeValidatorCount).to.be.equal(1)
  })

  it('again select permissioned pool and register a validator', async function () {
    await env.staderStakingPoolManager.updatePoolWeights(0, 100)
    await env.staderStakingPoolManager
      .connect(adr.staker4)
      .deposit(adr.staker4.address, { value: ethers.utils.parseEther('12') })

    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('20') })
    await env.staderStakingPoolManager.selectPool()

    expect(await provider.getBalance(env.staderPermissionedStakePool.address)).to.be.equal(
      ethers.utils.parseEther('32')
    )
    await env.staderPermissionedStakePool.depositEthToDepositContract()

    expect(await provider.getBalance(env.staderPermissionedStakePool.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('96'))
    expect(await env.validatorRegistry.registeredValidatorCount()).to.be.equal(3)
    const permissionedOperatorIndex = await env.operatorRegistry.getOperatorIndexById(1)
    const permissionedOperator = await env.operatorRegistry.operatorRegistry(permissionedOperatorIndex)
    expect(permissionedOperator.activeValidatorCount).to.be.equal(2)
  })

  it('poolManager balance again crosses 32 eth, but no permissioned validator left', async function () {
    await env.staderStakingPoolManager
      .connect(adr.staker4)
      .deposit(adr.staker4.address, { value: ethers.utils.parseEther('12') })

    await env.staderStakingPoolManager
      .connect(adr.staker5)
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('20') })
    await env.staderStakingPoolManager.selectPool()
    expect(env.staderPermissionedStakePool.depositEthToDepositContract()).to.be.revertedWith(
      'stand by permissioned validator not available'
    )
  })

  it('revert while updating pool weights', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updatePoolWeights(50, 50)).to.be.reverted
    expect(env.staderStakingPoolManager.updatePoolWeights(80, 50)).to.be.revertedWith('Invalid weights')
  })

  it('revert while updating permission less pool address', async () => {
    expect(
      env.staderStakingPoolManager
        .connect(adr.staker1)
        .updateStaderPermissionLessStakePoolAddresses(env.staderPermissionLessPool.address)
    ).to.be.reverted
    expect(
      env.staderStakingPoolManager.updateStaderPermissionLessStakePoolAddresses(adr.ZERO_ADDRESS)
    ).to.be.revertedWith('Address cannot be zero')
  })

  it('revert while updating stader permissioned pool address', async () => {
    expect(
      env.staderStakingPoolManager
        .connect(adr.staker1)
        .updateStaderPermissionedPoolAddresses(env.staderPermissionedStakePool.address)
    ).to.be.reverted
    expect(env.staderStakingPoolManager.updateStaderPermissionedPoolAddresses(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating min deposit', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateMinDepositLimit(1)).to.be.reverted
    expect(env.staderStakingPoolManager.updateMinDepositLimit(0)).to.be.revertedWith('invalid minDeposit value')
  })

  it('revert while updating max deposit', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateMaxDepositLimit(50)).to.be.reverted
    expect(env.staderStakingPoolManager.updateMaxDepositLimit(0.5)).to.be.revertedWith('invalid maxDeposit value')
  })

  it('revert while updating ethX address', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateEthXAddress(env.staderPermissionedStakePool.address))
      .to.be.reverted
    expect(env.staderStakingPoolManager.updateEthXAddress(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating Socializing Pool address', async () => {
    expect(
      env.staderStakingPoolManager
        .connect(adr.staker1)
        .updateSocializingPoolAddress(env.staderPermissionedStakePool.address)
    ).to.be.reverted
    expect(env.staderStakingPoolManager.updateSocializingPoolAddress(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })

  it('revert while updating stader oracle', async () => {
    expect(env.staderStakingPoolManager.connect(adr.staker1).updateStaderOracle(env.staderOracle.address)).to.be
      .reverted
    expect(env.staderStakingPoolManager.updateStaderOracle(adr.ZERO_ADDRESS)).to.be.revertedWith(
      'Address cannot be zero'
    )
  })
})
