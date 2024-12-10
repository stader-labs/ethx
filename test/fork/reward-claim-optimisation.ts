import { ethers, network } from "hardhat";
import "dotenv/config";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";

const PROXY_OWNER = "0x1112D5C55670Cb5144BF36114C20a122908068B9"
const PROXY_ADMIN = "0x67B12264Ca3e0037Fc7E22F2457b42643a04C86e";
const OPERATOR_REWARDS_COLLECTOR_ADDRESS = "0x84ffDC9De310144D889540A49052F6d1AdB2C335";
const OPERATOR = "0xb851788Fa34B0d9215F54531061D4e2e06A74AEE"
 
async function setForkBlock(blockNumber: number) {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.PROVIDER_URL_MAINNET,
          blockNumber: blockNumber,
        },
      },
    ],
  });
}

async function configureNewContract (contractName: String, contractAddress: String) {
  await setBalance(PROXY_OWNER, ethers.parseEther("1"))
  await impersonateAccount(PROXY_OWNER)

  const impersonatedProxyOwner = await ethers.getSigner(PROXY_OWNER);
  
  const contractFactory = await ethers.getContractFactory(contractName);
  const contractImpl = await contractFactory.deploy();
  console.log(`${contractName} Implementation deployed to:`, await contractImpl.getAddress());

  const proxyAdminContract = await ethers.getContractAt("ProxyAdmin", PROXY_ADMIN);
  await proxyAdminContract.connect(impersonatedProxyOwner).upgrade(contractAddress, await contractImpl.getAddress());

  const contract = await ethers.getContractAt(contractName, contractAddress)
  
  return contract;
}

describe("Gas Coverage", function () {
  it("should consume less gas after upgrade", async () => {
    await setForkBlock(21270988);
    await setBalance(OPERATOR, ethers.parseEther("100"))
    await impersonateAccount(OPERATOR);
    const impersonatedOperator = await ethers.getSigner(OPERATOR);

    const newOperatorRewardsCollector = await configureNewContract("OperatorRewardsCollector", OPERATOR_REWARDS_COLLECTOR_ADDRESS);
    
    // Firing a txn with updated contracts
    const claimTxn = await newOperatorRewardsCollector.connect(impersonatedOperator).claim();
    const claimTxnReceipt = await claimTxn.wait();
    console.log("Claim Txn Gas Estimate:", claimTxnReceipt.gasUsed);
  });
});
