const { expect } = require('chai')
const path = require('path')
const { setupAddresses, setupEnvironment } = require('./utils')

let adr
let env: any

describe('environmentSetupTest', () => {
  beforeEach(async () => {
    adr = await setupAddresses()
    env = await setupEnvironment(adr.staderOwner, adr.ssvOwner)
  })

  describe('when setting up the environment', () => {
    describe('when deploying the ssvNetwork', () => {
      it('should not revert', async () => {
        console.log('env.ssvNetwork.address ', env.ssvNetwork.address);
        await expect(env.ssvNetwork.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.ssvRegistry.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.ssvToken.address).to.not.be.empty
      })
    })

    describe('when deploying stader contracts', () => {
      it('should not revert', async () => {
        await expect(env.ethxToken.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.validatorRegistry.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderSSVPool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.StaderManagedStakePool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderStakingPoolManager.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.ELRewardContract.address).to.not.be.empty
      })
    })
  })
})
