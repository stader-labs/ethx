import '@nomicfoundation/hardhat-chai-matchers'
const { expect } = require('chai')
const { setupAddresses, setupEnvironment } = require('./utils')

let adr: any
let env: any

describe('ethX token tests', () => {
  beforeEach(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  describe('when performing common actions', () => {
    describe('when minting tokens', () => {
      it('should revert when not role', async () => {
        await expect(env.ethxToken.connect(adr.staker1).mint(adr.staker1.address, 10000)).to.be.reverted
      })
      it('should not revert when role', async () => {
        await expect(env.ethxToken.connect(adr.staderOwner).mint(adr.staker1.address, 10)).to.not.be.reverted
      })
    })

    describe('when burning tokens', () => {
      beforeEach(async () => {
        await env.ethxToken.connect(adr.staderOwner).mint(adr.staker1.address, 100)
      })
      it('should revert when not role', async () => {
        await expect(env.ethxToken.connect(adr.staker1).burnFrom(adr.staker1.address, 10)).to.be.reverted
      })
      it('should not revert when role', async () => {
        await expect(env.ethxToken.connect(adr.staderOwner).burnFrom(adr.staker1.address, 10)).to.not.be.reverted
      })
    })

    describe('when transfering tokens', () => {
      beforeEach(async () => {
        await env.ethxToken.connect(adr.staderOwner).mint(adr.staker1.address, 100)
      })
      it('should not revert', async () => {
        await env.ethxToken.connect(adr.staker1).transfer(adr.staker2.address, 10)
        expect(await env.ethxToken.balanceOf(adr.staker2.address)).to.be.equal(10)
        await env.ethxToken.connect(adr.staker2).transfer(adr.staker3.address, 5)
        expect(await env.ethxToken.balanceOf(adr.staker3.address)).to.be.equal(5)
      })
    })
  })
})
