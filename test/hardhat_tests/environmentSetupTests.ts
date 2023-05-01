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
        await expect(env.ethDeposit.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.ethxToken.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderOracle.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.userWithdrawManager.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderStakingPoolManager.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.socializingPoolContract.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.vaultFactoryInstance.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.poolUtilsInstance.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.permissionedNodeRegistry.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.permissionlessNodeRegistry.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderPermissionedPool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.staderPermissionLessPool.address).to.not.be.empty
      })

      it('should not revert', async () => {
        await expect(env.poolSelector.address).to.not.be.empty
      })
    })
  })
})
