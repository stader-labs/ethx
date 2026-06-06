// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./SunsetForkBase.sol";
import { MainnetAddresses } from "./MainnetAddresses.sol";

import { IStaderOracle, WithdrawnValidators } from "contracts/interfaces/IStaderOracle.sol";
import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";

/// @notice Helpers for mocked beacon-exit cascades across all sheet operators.
abstract contract AllOperatorsExitLib is SunsetForkBase {
    uint8 internal constant VALIDATOR_DEPOSITED = 4;
    string internal constant INVENTORY_PATH = "./test/fork/sunset/snapshots/all-operators-validator-inventory.json";

    struct ValidatorExitRow {
        bytes pubkey;
        address withdrawVault;
    }

    struct CascadeResult {
        uint256 validatorsTargeted;
        uint256 oracleBatches;
        uint256 quorumSubmissionsAccepted;
        uint256 nonTerminalPre;
        uint256 nonTerminalPost;
        bool cascadeApplied;
    }

    function _collectDepositedValidatorsFromInventory(
        address operator
    ) internal returns (ValidatorExitRow[] memory rows, uint8 poolId) {
        string memory raw = vm.readFile(INVENTORY_PATH);
        uint256 operatorCount = vm.parseJsonUint(raw, "$.operatorCount");

        for (uint256 i = 0; i < operatorCount; i++) {
            string memory base = string.concat("$.operators[", vm.toString(i), "].");
            if (vm.parseJsonAddress(raw, string.concat(base, "operatorAddress")) != operator) continue;

            poolId = uint8(vm.parseJsonUint(raw, string.concat(base, "poolId")));
            uint256 validatorCount = vm.parseJsonUint(raw, string.concat(base, "validatorCount"));

            rows = new ValidatorExitRow[](validatorCount);
            uint256 found;
            for (uint256 j = 0; j < validatorCount; j++) {
                string memory vbase = string.concat(base, "validators[", vm.toString(j), "].");
                if (vm.parseJsonUint(raw, string.concat(vbase, "statusCode")) != VALIDATOR_DEPOSITED) continue;
                rows[found] = ValidatorExitRow({
                    pubkey: vm.parseJsonBytes(raw, string.concat(vbase, "pubkey")),
                    withdrawVault: vm.parseJsonAddress(raw, string.concat(vbase, "withdrawVaultAddress"))
                });
                found++;
            }

            if (found < validatorCount) {
                ValidatorExitRow[] memory trimmed = new ValidatorExitRow[](found);
                for (uint256 j = 0; j < found; j++) trimmed[j] = rows[j];
                rows = trimmed;
            }
            return (rows, poolId);
        }

        revert("operator missing from inventory JSON");
    }

    function _readNonTerminalKeys(address operatorAddr) internal view returns (uint256) {
        (bool ok, bytes memory data) = MainnetAddresses.SD_COLLATERAL.staticcall(
            abi.encodeWithSignature("getOperatorInfo(address)", operatorAddr)
        );
        if (!ok) return 0;
        (, , uint256 nonTerminal) = abi.decode(data, (uint8, uint256, uint256));
        return nonTerminal;
    }

    function _runExitCascadeForOperator(
        Sheet memory sheet,
        OperatorRow memory op
    ) internal returns (CascadeResult memory result) {
        ValidatorExitRow[] memory rows;
        uint8 poolId;
        (rows, poolId) = _collectDepositedValidatorsFromInventory(op.addr);

        result.validatorsTargeted = rows.length;
        result.nonTerminalPre = _readNonTerminalKeys(op.addr);

        if (rows.length == 0) {
            result.nonTerminalPost = result.nonTerminalPre;
            return result;
        }

        (result.oracleBatches, result.quorumSubmissionsAccepted) = _executeExitBatches(sheet, poolId, rows);
        result.nonTerminalPost = _readNonTerminalKeys(op.addr);
        result.cascadeApplied = result.nonTerminalPost < result.nonTerminalPre;
    }

    function _executeExitBatches(
        Sheet memory sheet,
        uint8 poolId,
        ValidatorExitRow[] memory rows
    ) internal returns (uint256 batches, uint256 quorumAccepted) {
        uint256 batchSize = IStaderConfig(MainnetAddresses.STADER_CONFIG).getWithdrawnKeyBatchSize();

        for (uint256 start = 0; start < rows.length; start += batchSize) {
            uint256 end = start + batchSize;
            if (end > rows.length) end = rows.length;

            bytes[] memory pubkeys = _pubkeysForBatch(rows, start, end);
            uint256 reportBlock = IStaderOracle(MainnetAddresses.STADER_ORACLE).getWithdrawnValidatorReportableBlock();
            WithdrawnValidators memory payload = WithdrawnValidators({
                poolId: poolId,
                reportingBlockNumber: reportBlock,
                sortedPubkeys: pubkeys
            });

            quorumAccepted += _submitQuorum(sheet, payload);
            batches++;

            if (end < rows.length) vm.roll(block.number + 14_400);
        }
    }

    function _pubkeysForBatch(
        ValidatorExitRow[] memory rows,
        uint256 start,
        uint256 end
    ) internal returns (bytes[] memory pubkeys) {
        pubkeys = new bytes[](end - start);
        for (uint256 i = start; i < end; i++) {
            ValidatorExitRow memory row = rows[i];
            pubkeys[i - start] = row.pubkey;
            if (row.withdrawVault != address(0)) vm.deal(row.withdrawVault, 32 ether);
        }
    }

    function _submitQuorum(Sheet memory sheet, WithdrawnValidators memory payload) internal returns (uint256 accepted) {
        for (uint256 q = 0; q < sheet.custody.oracleQuorum.length; q++) {
            vm.prank(sheet.custody.oracleQuorum[q]);
            try IStaderOracle(MainnetAddresses.STADER_ORACLE).submitWithdrawnValidators(payload) {
                accepted++;
            } catch {}
        }
    }
}
