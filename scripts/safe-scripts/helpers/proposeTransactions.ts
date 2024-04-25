import SafeApiKit from "@safe-global/api-kit";
import Safe, { EthersAdapter } from "@safe-global/protocol-kit";
import { SafeTransactionDataPartial } from "@safe-global/safe-core-sdk-types";
import { ethers } from "hardhat";

import addressesJson from "../address.json";

const addresses: any = addressesJson;

async function main(transactions: SafeTransactionDataPartial[]) {
  const inquirer = await import('inquirer');

  const [signer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (addresses[network.name].safe === undefined) {
    throw new Error(`Chain name mismatch got ${network.name} with no safe address in address.json`);
  }
  const safeAddress = addresses[network.name].safe;

  // Create EthAdapter instance
  const ethAdapter = new EthersAdapter({
    ethers,
    signerOrProvider: signer,
  });

  // Create Safe instance
  const safe = await Safe.create({
    ethAdapter,
    safeAddress,
  });

  // Create Safe API Kit instance
  const service = new SafeApiKit({
    chainId: network.chainId,
  });
  // Fetch the current nonce from the Safe
  const currentNonce = await service.getNextNonce(safeAddress);
  const firstNonce = await safe.getNonce();
  // Ask user for nonce selection
  const answers = await inquirer.prompt([
    {
      type: "list",
      name: "nonceOption",
      message: "Select nonce option:",
      choices: [`Use next available nonce "${currentNonce}"`, `Use first nonce "${firstNonce}"`, "Specify nonce"],
    },
    {
      type: "number",
      name: "specifiedNonce",
      message: "Enter the nonce:",
      when: (answers) => answers.nonceOption === "Specify nonce",
      validate: (value) => {
        const number = parseInt(value, 10);
        return (
          number >= firstNonce || `Nonce must be greater than or equal to the first available nonce (${firstNonce}).`
        );
      },
    },
  ]);

  const nonce =
    answers.nonceOption === "Specify nonce"
      ? answers.specifiedNonce
      : answers.nonceOption.startsWith("Use first nonce")
        ? firstNonce
        : currentNonce;
  console.log(`Selected nonce: ${nonce}`);

  const safeTransaction = await safe.createTransaction({ transactions });
  safeTransaction.data.nonce = nonce;
  const senderAddress = await signer.getAddress();
  const safeTxHash = await safe.getTransactionHash(safeTransaction);
  const signature = await safe.signHash(safeTxHash);

  // Propose transaction to the service
  await service.proposeTransaction({
    safeAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress,
    senderSignature: signature.data,
  });

  console.log("Proposed a transaction with Safe:", safeAddress);
  console.log("- safeTxHash:", safeTxHash);
  console.log("- Sender:", senderAddress);
  console.log("- Sender signature:", signature.data);
}

export default main;
