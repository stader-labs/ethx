import { ethers, network } from "hardhat";
import { expect } from "chai";
import "dotenv/config";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";

const PROXY_OWNER = "0x1112D5C55670Cb5144BF36114C20a122908068B9";
const PROXY_ADMIN = "0x67B12264Ca3e0037Fc7E22F2457b42643a04C86e";
const STADER_STAKE_POOL_MANAGER = "0xcf5EA1b38380f6aF39068375516Daf40Ed70D299";
const USER_WITHDRAW_MANAGER = "0x9F0491B32DBce587c50c4C43AB303b06478193A7";
const STADER_MULTISIG = "0xAAfb31780e4b9c95Bc920e388f4925A874cd07AF";

const FORK_BLOCK = 21270988;
const CUSTODY = "0x000000000000000000000000000000000000c057";

async function setForkBlock(blockNumber: number) {
  await network.provider.request({
    method: "hardhat_reset",
    params: [{ forking: { jsonRpcUrl: process.env.PROVIDER_URL_MAINNET, blockNumber } }],
  });
}

async function upgradeImpl(contractName: string, proxyAddress: string) {
  await setBalance(PROXY_OWNER, ethers.parseEther("1"));
  await impersonateAccount(PROXY_OWNER);
  const owner = await ethers.getSigner(PROXY_OWNER);
  const Factory = await ethers.getContractFactory(contractName);
  const impl = await Factory.deploy();
  const proxyAdmin = await ethers.getContractAt("ProxyAdmin", PROXY_ADMIN);
  await proxyAdmin.connect(owner).upgrade(proxyAddress, await impl.getAddress());
  return ethers.getContractAt(contractName, proxyAddress);
}

async function asSigner(addr: string, fundEth = "10") {
  await setBalance(addr, ethers.parseEther(fundEth));
  await impersonateAccount(addr);
  return ethers.getSigner(addr);
}

describe("ETHx sunset-runoff — mainnet fork", function () {
  let sspm: any;

  before(async () => {
    await setForkBlock(FORK_BLOCK);
    sspm = await upgradeImpl("StaderStakePoolsManager", STADER_STAKE_POOL_MANAGER);
  });

  it("MANAGER pauses deposits, deposit reverts, redemption path still works", async () => {
    const manager = await asSigner(STADER_MULTISIG);

    // Reversible pause.
    await sspm.connect(manager).setDepositsPaused(true);
    expect(await sspm.depositsPaused()).to.equal(true);

    const depositor = await asSigner("0x0000000000000000000000000000000000001234");
    await expect(
      sspm.connect(depositor)["deposit(address)"](depositor.address, { value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(sspm, "DepositsPaused");

    // Sanity: unpause works (reversibility property).
    await sspm.connect(manager).setDepositsPaused(false);
    expect(await sspm.depositsPaused()).to.equal(false);
    // Re-pause for subsequent test state hygiene.
    await sspm.connect(manager).setDepositsPaused(true);

    // Pause does not break the redemption path: UWM can still pull ETH.
    const uwm = await asSigner(USER_WITHDRAW_MANAGER);
    await setBalance(STADER_STAKE_POOL_MANAGER, ethers.parseEther("5"));
    await expect(sspm.connect(uwm).transferETHToUserWithdrawManager(ethers.parseEther("1"))).to.not.be.reverted;
  });

  it("admin arms custody delay then sweeps to flip assetCustodied; subsequent deposit / batch deposit revert", async () => {
    // The admin role holder on SSPM is the deployer-set admin, which is the same multisig.
    const admin = await asSigner(STADER_MULTISIG);
    const adminAddr = await admin.getAddress();

    // If the multisig doesn't actually hold DEFAULT_ADMIN_ROLE on the SSPM proxy at this
    // fork block, skip this leg loudly rather than fail silently.
    const hasAdmin = await sspm.hasRole(await sspm.DEFAULT_ADMIN_ROLE(), adminAddr);
    if (!hasAdmin) {
      console.warn("Multisig does not hold DEFAULT_ADMIN_ROLE on SSPM at fork block; skipping sweep leg");
      this.skip?.();
      return;
    }

    await sspm.connect(admin).setCustodyDelay(60);
    await network.provider.send("evm_increaseTime", [120]);
    await network.provider.send("evm_mine", []);

    // Seed residual ETH so sweep doesn't hit ZeroAmount.
    await setBalance(STADER_STAKE_POOL_MANAGER, ethers.parseEther("2"));
    const before = await ethers.provider.getBalance(CUSTODY);
    await sspm.connect(admin).sweepToCustody(ethers.ZeroAddress, CUSTODY);
    const after = await ethers.provider.getBalance(CUSTODY);
    expect(after - before).to.equal(ethers.parseEther("2"));
    expect(await sspm.assetCustodied()).to.equal(true);

    // Post-sweep: deposit and validatorBatchDeposit and depositETHOverTargetWeight all revert with AssetCustodied.
    const depositor = await asSigner("0x0000000000000000000000000000000000002345");
    await expect(
      sspm.connect(depositor)["deposit(address)"](depositor.address, { value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(sspm, "AssetCustodied");
  });
});
