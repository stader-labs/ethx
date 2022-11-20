const { expect } = require('chai')

describe('EthX contract', function () {
  it('Deployment should assign the total supply of tokens to the owner', async function () {
    const [owner] = await ethers.getSigners()

    const EthX = await ethers.getContractFactory('ETHX')

    const hardhatEthX = await EthX.deploy()

    const ownerBalance = await hardhatEthX.balanceOf(owner.address)
    expect(await hardhatEthX.totalSupply()).to.equal(ownerBalance)
  })
})
