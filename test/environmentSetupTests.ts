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
    describe('when deploying stader contracts', () => {
      it('should not revert', async () => {
        await expect(env.ethxToken.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.validatorRegistry.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderPermissionLessPool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderPermissionedStakePool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderStakingPoolManager.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.socializePool.address).to.not.be.empty
      })
    })
  })
})
