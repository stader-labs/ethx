import upgradeHelper from "./helpers/upgrade";
import networkAddresses from "./address.json";
import proposeTransactions from "./helpers/proposeTransactions";
import {  MetaTransactionData } from "@safe-global/safe-core-sdk-types";

async function main(networks: { [networkName: string]: { contracts: { name: string; address: string }[] } }) {
  const networkName = await hre.network.name;
  const networkContracts = networks[networkName].contracts;
  const targets = [];
  const values = [];
  const params = [];
  console.log(`Checking contracts on network "${networkName}":`, "\n");

  for (let { name, address } of networkContracts) {
    const { to, value, data } = await upgradeHelper(address, name);
    targets.push(to);
    values.push(value);
    params.push(data);
  }
  const multisigData = await buildMultiSigTx(targets, values, params);
  await proposeTransactions(multisigData);
}

async function buildMultiSigTx(targets: string[], values: string[], params: string[]): Promise<MetaTransactionData[]> {
  const safeTransactionData: MetaTransactionData[] = [];
  for (let i = 0; i < targets.length; ++i) {
    const safeTxData: MetaTransactionData = {
      to: targets[i],
      data: params[i],
      value: values[i],
      operation: 0,
    };
    safeTransactionData.push(safeTxData);
  }
  return safeTransactionData;
}

main(networkAddresses)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
