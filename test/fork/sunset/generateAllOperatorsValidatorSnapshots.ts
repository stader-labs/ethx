import fs from "node:fs";
import path from "node:path";
import hre from "hardhat";
import { ethers } from "ethers";
import "dotenv/config";

/**
 * Scan every operator on the runoff sheet at the freeze block and write
 * `snapshots/all-operators-validator-inventory.json` (read-only inventory).
 *
 * Pair with `AllOperatorsValidatorExitTest` which mocks exits and writes
 * `snapshots/all-operators-validator-exit-report.json`.
 *
 * Usage:
 *   npm run snapshot:all-operator-validators
 */

const PERMISSIONED_NODE_REGISTRY = "0xaf42d795A6D279e9DCc19DC0eE1cE3ecd4ecf5dD";
const PERMISSIONLESS_NODE_REGISTRY = "0x4f4Bfa0861F62309934a5551E0B2541Ee82fdcF1";
const SD_COLLATERAL = "0x7Af4730cc8EbAd1a050dcad5c03c33D2793EE91f";
const DEFAULT_FORK_BLOCK = 21_500_000;
const PAGE_SIZE = 50;

const STATUS_LABELS = [
  "INITIALIZED",
  "INVALID_SIGNATURE",
  "FRONT_RUN",
  "PRE_DEPOSIT",
  "DEPOSITED",
  "WITHDRAWN",
] as const;

const TERMINAL_STATUSES = new Set([1, 2, 5]);

interface RunoffOperatorRow {
  address: string;
  pool: string;
  totalKeys: string;
  nonTerminalKeys: string;
  status: string;
  contact: string;
}

interface RunoffSheet {
  operators: RunoffOperatorRow[];
}

interface ValidatorRow {
  index: number;
  statusCode: number;
  status: string;
  pubkey: string;
  withdrawVaultAddress: string;
  operatorId: number;
  depositBlock: number;
  withdrawnBlock: number;
}

function rpcUrl(): string {
  const url = process.env.PROVIDER_URL_MAINNET ?? process.env.ETH_RPC_URL;
  if (!url) throw new Error("Set PROVIDER_URL_MAINNET or ETH_RPC_URL");
  return url;
}

function registryForPool(pool: string): string {
  return pool === "Permissioned" ? PERMISSIONED_NODE_REGISTRY : PERMISSIONLESS_NODE_REGISTRY;
}

function statusLabel(statusCode: number): string {
  return STATUS_LABELS[statusCode] ?? "UNKNOWN";
}

function isNonTerminal(statusCode: number): boolean {
  return !TERMINAL_STATUSES.has(statusCode);
}

async function scanOperator(
  operator: RunoffOperatorRow,
  blockTag: number,
  provider: ethers.JsonRpcProvider
) {
  const address = ethers.getAddress(operator.address);
  const registryAddr = registryForPool(operator.pool);
  const contractName =
    operator.pool === "Permissioned" ? "PermissionedNodeRegistry" : "PermissionlessNodeRegistry";
  const nodeRegistry = await hre.ethers.getContractAt(contractName, registryAddr, provider);
  const sdCollateral = await hre.ethers.getContractAt("SDCollateral", SD_COLLATERAL, provider);

  let operatorId = 0n;
  let totalKeys = 0;
  const validators: ValidatorRow[] = [];
  let nonTerminalOnChain = 0;

  try {
    operatorId = await nodeRegistry.operatorIDByAddress(address, { blockTag });
    if (operatorId === 0n) {
      return { address, operator, operatorId: 0, totalKeys: 0, validators, nonTerminalOnChain: 0, nonTerminalFromSd: 0, poolId: 0, skipped: "not onboarded" };
    }

    totalKeys = Number(await nodeRegistry.getOperatorTotalKeys(operatorId, { blockTag }));
    const operatorInfo = await sdCollateral.getOperatorInfo(address, { blockTag });
    const poolId = Number(operatorInfo[0]);
    const nonTerminalFromSd = Number(operatorInfo[2]);
    const pageCount = Math.ceil(totalKeys / PAGE_SIZE);

    for (let page = 1; page <= pageCount; page++) {
      const batch = await nodeRegistry.getValidatorsByOperator(address, page, PAGE_SIZE, { blockTag });
      for (const validator of batch) {
        const statusCode = Number(validator.status);
        if (isNonTerminal(statusCode)) nonTerminalOnChain++;
        validators.push({
          index: validators.length,
          statusCode,
          status: statusLabel(statusCode),
          pubkey: ethers.hexlify(validator.pubkey),
          withdrawVaultAddress: validator.withdrawVaultAddress,
          operatorId: Number(validator.operatorId),
          depositBlock: Number(validator.depositBlock),
          withdrawnBlock: Number(validator.withdrawnBlock),
        });
      }
    }

    return {
      address,
      operator,
      operatorId: Number(operatorId),
      totalKeys,
      validators,
      nonTerminalOnChain,
      nonTerminalFromSd,
      poolId,
      skipped: null,
    };
  } catch (err) {
    return {
      address,
      operator,
      operatorId: Number(operatorId),
      totalKeys,
      validators,
      nonTerminalOnChain,
      nonTerminalFromSd: 0,
      poolId: 0,
      skipped: err instanceof Error ? err.message : "scan failed",
    };
  }
}

async function main() {
  const forkBlock = Number(process.env.FORK_BLOCK ?? DEFAULT_FORK_BLOCK);
  const blockTag = forkBlock;
  const provider = new ethers.JsonRpcProvider(rpcUrl());
  const sheetPath = path.join(__dirname, "fixtures", "runoff-sheet.json");
  const sheet = JSON.parse(fs.readFileSync(sheetPath, "utf8")) as RunoffSheet;

  const operators = [];
  for (const row of sheet.operators) {
    console.log(`scanning ${row.address} (${row.pool})`);
    operators.push(await scanOperator(row, blockTag, provider));
  }

  const payload = {
    freezeBlock: forkBlock,
    operatorCount: sheet.operators.length,
    operators: operators.map((op) => ({
      operatorAddress: op.address,
      operatorId: op.operatorId,
      pool: op.operator.pool,
      sheetStatus: op.operator.status,
      contact: op.operator.contact,
      sheetTotalKeys: Number(op.operator.totalKeys),
      sheetNonTerminalKeys: Number(op.operator.nonTerminalKeys),
      totalKeys: op.totalKeys,
      validatorCount: op.validators.length,
      nonTerminalKeysOnChain: op.nonTerminalOnChain,
      nonTerminalKeysSdCollateral: op.nonTerminalFromSd,
      poolId: op.poolId,
      skippedReason: op.skipped,
      validators: op.validators,
    })),
  };

  const outPath = path.join(__dirname, "snapshots", "all-operators-validator-inventory.json");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`wrote ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
