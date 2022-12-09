import '@nomicfoundation/hardhat-chai-matchers'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'
import { startWorkflow } from '../scripts/1_workflowManager'
import deposit from '../scripts/deposits/deposit0.json'
import SSV_POOL_CONTRACT_ABI from '../artifacts/contracts/StaderSSVStakePool.sol/StaderSSVStakePool.json'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')
const provider = waffle.provider

const KEYSTORE_PASSWORD = process.env.KEYSTORE_PASSWORD
const OPERATOR_INDEX = 0

let adr: any
let env: any

describe('ssv pool test', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })
  it('when more than 32 ETH have been staked', async () => {
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
  it('ssv pool should have 32 eth', async () => {
    expect(await provider.getBalance(env.staderStakingPoolManager.address)).to.be.equal(ethers.utils.parseEther('18'))
    expect(await provider.getBalance(env.staderSSVPool.address)).to.be.equal(ethers.utils.parseEther('32'))
  })
  it('should have 1 validator available for creation', async () => {
    const ssvPoolBalance = await provider.getBalance(env.staderSSVPool.address)
    expect(ssvPoolBalance.div('32')).to.be.within(ethers.utils.parseEther('1'), ethers.utils.parseEther('2'))
  })
  it('should send 32 eth to deposit contract', async () => {
    await expect(
      env.staderSSVPool.depositEthToDepositContract(
        '0x' + deposit.pubkey,
        '0x' + deposit.withdrawal_credentials,
        '0x' + deposit.signature,
        '0x' + deposit.deposit_data_root
      )
    ).to.be.not.reverted
    expect(await provider.getBalance(env.staderSSVPool.address)).to.be.equal(ethers.utils.parseEther('0'))
    expect(await provider.getBalance(env.ethDeposit.address)).to.be.equal(ethers.utils.parseEther('32'))
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(1)
  })

  it('should register validator to network', async () => {
    expect(await env.validatorRegistry.validatorCount()).to.be.equal(1)
    expect(await env.staderSSVPool.staderSSVRegistryCount()).to.be.equal(0)
    console.log('ssv pool instance ', env.staderSSVPool.address)
    await expect(
      startWorkflow(KEYSTORE_PASSWORD, OPERATOR_INDEX, 1)
    ).to.not.be.reverted
    expect(await env.staderSSVPool.staderSSVRegistryCount()).to.be.equal(1)
  })
  it('check validator index in ssvRegistry and validator registry', async () => {
    expect(await env.validatorRegistry.getValidatorIndexByPublicKey('0x' + deposit.pubkey)).to.be.equal(0)
    expect(await env.staderSSVPool.getValidatorIndexByPublicKey('0x' + deposit.pubkey)).to.be.equal(0)
  })
})
