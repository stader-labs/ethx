import '@nomicfoundation/hardhat-chai-matchers'
import 'dotenv/config'
import { ethers, waffle } from 'hardhat'

const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')

let adr: any
let env: any

describe('stader oracle tests', () => {
  before(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  it('revert while submitting report from an untrusted node ', async function () {
    let latestBlock = await ethers.provider.getBlock('latest')
    expect(
      env.staderOracle.connect(adr.staker1).submitBalances(latestBlock.number - 1, 150, 100, 100, 0)
    ).to.be.revertedWith('Not a trusted node')
  })

  it('revert while submitting report for future block ', async function () {
    let latestBlock = await ethers.provider.getBlock('latest')
    expect(
      env.staderOracle.connect(adr.staderOwner).submitBalances(latestBlock.number + 1, 150, 100, 100, 0)
    ).to.be.revertedWith('Balances can not be submitted for a future block')
  })

  it('revert while submitting report for previous block than lastBlockNumber', async function () {
    expect(env.staderOracle.connect(adr.staderOwner).submitBalances(0, 150, 100, 100, 0)).to.be.revertedWith(
      'Network balances for an equal or higher block are set'
    )
  })

  it('revert while submitting report invalid balance', async function () {
    let latestBlock = await ethers.provider.getBlock('latest')
    expect(
      env.staderOracle.connect(adr.staderOwner).submitBalances(latestBlock.number - 1, 100, 150, 100, 0)
    ).to.be.revertedWith('Invalid network balances')
  })

  it('revert while submitting duplicate report', async function () {
    let latestBlock = await ethers.provider.getBlock('latest')
    await env.staderOracle.connect(adr.staderOwner).submitBalances(latestBlock.number - 1, 150, 100, 100, 0)
    expect(
      env.staderOracle.connect(adr.staderOwner).submitBalances(latestBlock.number - 1, 150, 100, 100, 0)
    ).to.be.revertedWith('Duplicate submission from node')
  })
})
