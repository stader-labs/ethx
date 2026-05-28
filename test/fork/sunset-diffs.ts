import { ethers, network } from "hardhat";
import { expect } from "chai";
import "dotenv/config";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";

const PROXY_OWNER = "0x1112D5C55670Cb5144BF36114C20a122908068B9";
const PROXY_ADMIN = "0x67B12264Ca3e0037Fc7E22F2457b42643a04C86e";
const STADER_CONFIG = "0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB";
const STADER_STAKE_POOL_MANAGER = "0xcf5EA1b38380f6aF39068375516Daf40Ed70D299";
const USER_WITHDRAW_MANAGER = "0x9F0491B32DBce587c50c4C43AB303b06478193A7";
const SD_UTILITY_POOL = "0xED6EE5049f643289ad52411E9aDeC698D04a9602";
const OPERATOR_REWARDS_COLLECTOR = "0x84ffDC9De310144D889540A49052F6d1AdB2C335";
const STADER_MULTISIG = "0xAAfb31780e4b9c95Bc920e388f4925A874cd07AF";

const FORK_BLOCK = 21270988;

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

describe("ETHx sunset diffs — mainnet fork", function () {
  let sspm: any;
  let orc: any;
  let sdup: any;
  let staderConfig: any;
  let sdToken: any;

  before(async () => {
    await setForkBlock(FORK_BLOCK);
    sspm = await upgradeImpl("StaderStakePoolsManager", STADER_STAKE_POOL_MANAGER);
    orc = await upgradeImpl("OperatorRewardsCollector", OPERATOR_REWARDS_COLLECTOR);
    sdup = await upgradeImpl("SDUtilityPool", SD_UTILITY_POOL);
    staderConfig = await ethers.getContractAt("StaderConfig", STADER_CONFIG);
    sdToken = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", await staderConfig.getStaderToken());
  });

  describe("Diff A — pauseDeposits", () => {
    it("MANAGER can pause deposits and deposit then reverts; UWM transfer still works", async () => {
      const manager = await asSigner(STADER_MULTISIG);
      await sspm.connect(manager).pauseDeposits();
      expect(await sspm.depositsPaused()).to.equal(true);

      const depositor = await asSigner("0x0000000000000000000000000000000000001234");
      await expect(
        sspm.connect(depositor)["deposit(address)"](depositor.address, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(sspm, "DepositsAreSunset");

      const uwm = await asSigner(USER_WITHDRAW_MANAGER);
      await setBalance(STADER_STAKE_POOL_MANAGER, ethers.parseEther("5"));
      await expect(sspm.connect(uwm).transferETHToUserWithdrawManager(ethers.parseEther("1"))).to.not.be
        .reverted;
    });
  });
});
