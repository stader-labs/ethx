import { OperationType, SafeTransactionDataPartial } from "@safe-global/safe-core-sdk-types";
import proposeTransactions from "./proposeTransactions";

// This file can be used to play around with the Safe Core SDK

async function main(to: string, value: string, data: string) {
  // Create transaction
  const safeTransactionData: SafeTransactionDataPartial = {
    to,
    value,
    data,
    operation: OperationType.Call,
  };
  await proposeTransactions([safeTransactionData]);
}

export default main;
