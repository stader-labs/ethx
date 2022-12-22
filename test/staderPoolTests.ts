import '@nomicfoundation/hardhat-chai-matchers'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'
import { registerValidator } from './helper/validatorRegistrationStaderPool'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')
const provider = waffle.provider

let adr: any
let env: any

describe('stader pool tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  it('when more than 32 ETH have been staked', async () => {
    console.log('Stader PoolManager is ', env.staderStakingPoolManager.address);
    await env.staderStakingPoolManager.updatePoolWeights(0, 100)
    await env.staderStakingPoolManager
      .connect(adr.staker1)
      .deposit(adr.staker1.address, { value: ethers.utils.parseEther('10') })
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
      .deposit(adr.staker5.address, { value: ethers.utils.parseEther('10') })
  })
  it('stader pool should have 32ETH in balance', async () => {
    expect(await provider.getBalance(env.StaderManagedStakePool.address)).to.be.equal(ethers.utils.parseEther('32'))
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('18'))
  })
  it('should have 1 validator available for creation', async () => {
    const staderPoolBalance = await provider.getBalance(env.StaderManagedStakePool.address)
    expect(staderPoolBalance.div('32')).to.be.within(ethers.utils.parseEther('1'), ethers.utils.parseEther('2'))
  })

  it('should register a new validator ', async () => {
    await registerValidator(env.StaderManagedStakePool)
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(1)
    expect(await provider.getBalance(env.StaderManagedStakePool.address)).to.be.equal(ethers.utils.parseEther('0'))
  })
})
