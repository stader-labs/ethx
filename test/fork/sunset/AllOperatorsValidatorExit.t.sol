// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { AllOperatorsExitLib } from "./helpers/AllOperatorsExitLib.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";
import { IStaderOracle } from "contracts/interfaces/IStaderOracle.sol";
import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";

/// @notice Loops every sheet operator with `nonTerminalKeys > 0`, mocks beacon
///         payouts, runs oracle `submitWithdrawnValidators` in batch-size
///         chunks, and writes `all-operators-validator-exit-report.json`.
///
///         Prerequisite: `npm run snapshot:all-operator-validators`
contract AllOperatorsValidatorExitTest is AllOperatorsExitLib {
    function test_AllOperatorsExitAndReport() public {
        Sheet memory sheet = _loadSheet();
        require(sheet.operators.length > 0, "operators slice empty");
        require(sheet.custody.oracleQuorum.length > 0, "oracle_quorum empty");

        uint256 batchSize = IStaderConfig(MainnetAddresses.STADER_CONFIG).getWithdrawnKeyBatchSize();
        uint256 reportBlock = IStaderOracle(MainnetAddresses.STADER_ORACLE).getWithdrawnValidatorReportableBlock();

        string memory root = "allOperatorsExit";
        vm.serializeUint(root, "freezeBlock", freezeBlock);
        vm.serializeUint(root, "withdrawnKeyBatchSize", batchSize);
        vm.serializeUint(root, "reportingBlockNumber", reportBlock);
        vm.serializeUint(root, "operatorCount", sheet.operators.length);
        vm.serializeString(root, "inventoryPath", INVENTORY_PATH);

        uint256 processedOperators;
        uint256 exitedOperators;
        uint256 skippedOperators;
        uint256 totalValidatorsExited;

        for (uint256 i = 0; i < sheet.operators.length; i++) {
            OperatorRow memory op = sheet.operators[i];
            if (op.nonTerminalKeys == 0) {
                skippedOperators++;
                continue;
            }

            processedOperators++;
            CascadeResult memory r = _runExitCascadeForOperator(sheet, op);

            if (r.validatorsTargeted == 0) {
                skippedOperators++;
            } else if (r.cascadeApplied) {
                exitedOperators++;
                totalValidatorsExited += r.validatorsTargeted;
            }

            string memory opKey = string.concat("op", vm.toString(i));
            vm.serializeAddress(opKey, "address", op.addr);
            vm.serializeString(opKey, "pool", op.pool);
            vm.serializeString(opKey, "status", op.status);
            vm.serializeString(opKey, "contact", op.contact);
            vm.serializeUint(opKey, "sheetNonTerminalKeys", op.nonTerminalKeys);
            vm.serializeUint(opKey, "nonTerminalPre", r.nonTerminalPre);
            vm.serializeUint(opKey, "nonTerminalPost", r.nonTerminalPost);
            vm.serializeUint(opKey, "validatorsTargeted", r.validatorsTargeted);
            vm.serializeUint(opKey, "validatorsExited", r.cascadeApplied ? r.validatorsTargeted : 0);
            vm.serializeUint(opKey, "oracleBatches", r.oracleBatches);
            vm.serializeUint(opKey, "quorumSubmissionsAccepted", r.quorumSubmissionsAccepted);
            string memory opJson = vm.serializeBool(opKey, "cascadeApplied", r.cascadeApplied);
            vm.serializeString(root, string.concat("operator_", vm.toString(i)), opJson);

            emit log_named_address("operator", op.addr);
            emit log_named_uint("  validatorsTargeted", r.validatorsTargeted);
            emit log_named_uint("  nonTerminal pre", r.nonTerminalPre);
            emit log_named_uint("  nonTerminal post", r.nonTerminalPost);
            emit log_named_uint("  oracleBatches", r.oracleBatches);
        }

        vm.serializeUint(root, "processedOperators", processedOperators);
        vm.serializeUint(root, "exitedOperators", exitedOperators);
        vm.serializeUint(root, "skippedOperators", skippedOperators);
        string memory payload = vm.serializeUint(root, "totalValidatorsExited", totalValidatorsExited);
        vm.writeJson(payload, "./test/fork/sunset/snapshots/all-operators-validator-exit-report.json");
    }
}
