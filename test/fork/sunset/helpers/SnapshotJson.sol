// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

/// @notice Read/write helper for the freeze-block snapshot JSON file
///         produced by `FreezeBlockSnapshotTest` and consumed by
///         downstream regression diffs.
abstract contract SnapshotJson is Test {
    struct ContractAggregates {
        uint256 ethBalance;
        uint256 ethXTotalSupply;
        uint256 sspmExchangeRate;
        uint256 sspmTotalAssets;
        uint256 sspmLastExcessEthDepositBlock;
        uint256 sdupSdBalance;
        uint256 sdupTotalUtilizedSD;
        uint256 sdupCTokenTotalSupply;
        uint256 sdupAccumulatedProtocolFee;
        uint256 sdupNextRequestId;
        uint256 sdupNextRequestIdToFinalize;
        uint256 sdupMinBlockDelayToFinalizeRequest;
        uint256 spPermissionedEth;
        uint256 spPermissionedSd;
        uint256 spPermissionedOperatorEthRewardsRemaining;
        uint256 spPermissionedOperatorSdRewardsRemaining;
        uint256 spPermissionlessEth;
        uint256 spPermissionlessSd;
        uint256 spPermissionlessOperatorEthRewardsRemaining;
        uint256 spPermissionlessOperatorSdRewardsRemaining;
        uint256 plpEth;
        uint256 orcEth;
        uint256 orcWethBalance;
        uint256 uwmEth;
        uint256 uwmNextRequestId;
        uint256 uwmNextRequestIdToFinalize;
        uint256 uwmMinBlockDelayToFinalizeWithdrawRequest;
        uint256 oracleTrustedNodesCount;
        uint256 oracleLastReportedErBlock;
        uint256 oracleLastReportedTotalEth;
        uint256 oracleLastReportedEthXSupply;
        uint256 treasuryEth;
        uint256 treasurySd;
    }

    /// @notice Default snapshot file location for the given block.
    function _snapshotPath(uint256 blockNumber) internal pure returns (string memory) {
        return string.concat("./test/fork/sunset/snapshots/freeze-snapshot-", vm.toString(blockNumber), ".json");
    }

    /// @notice Serialize aggregates + freeze metadata and write to disk.
    function _writeSnapshot(
        uint256 freezeBlock,
        uint256 timestamp,
        address custodyMultisig,
        ContractAggregates memory a
    ) internal {
        string memory key = "freezeSnapshot";
        vm.serializeUint(key, "freezeBlock", freezeBlock);
        vm.serializeUint(key, "timestamp", timestamp);
        vm.serializeAddress(key, "custodyMultisig", custodyMultisig);
        vm.serializeUint(key, "sspm_ethBalance", a.ethBalance);
        vm.serializeUint(key, "sspm_ethXTotalSupply", a.ethXTotalSupply);
        vm.serializeUint(key, "sspm_exchangeRate", a.sspmExchangeRate);
        vm.serializeUint(key, "sspm_totalAssets", a.sspmTotalAssets);
        vm.serializeUint(key, "sspm_lastExcessEthDepositBlock", a.sspmLastExcessEthDepositBlock);
        vm.serializeUint(key, "sdup_sdBalance", a.sdupSdBalance);
        vm.serializeUint(key, "sdup_totalUtilizedSD", a.sdupTotalUtilizedSD);
        vm.serializeUint(key, "sdup_cTokenTotalSupply", a.sdupCTokenTotalSupply);
        vm.serializeUint(key, "sdup_accumulatedProtocolFee", a.sdupAccumulatedProtocolFee);
        vm.serializeUint(key, "sdup_nextRequestId", a.sdupNextRequestId);
        vm.serializeUint(key, "sdup_nextRequestIdToFinalize", a.sdupNextRequestIdToFinalize);
        vm.serializeUint(key, "sdup_minBlockDelayToFinalizeRequest", a.sdupMinBlockDelayToFinalizeRequest);
        vm.serializeUint(key, "spPermissioned_ethBalance", a.spPermissionedEth);
        vm.serializeUint(key, "spPermissioned_sdBalance", a.spPermissionedSd);
        vm.serializeUint(
            key,
            "spPermissioned_operatorEthRewardsRemaining",
            a.spPermissionedOperatorEthRewardsRemaining
        );
        vm.serializeUint(key, "spPermissioned_operatorSdRewardsRemaining", a.spPermissionedOperatorSdRewardsRemaining);
        vm.serializeUint(key, "spPermissionless_ethBalance", a.spPermissionlessEth);
        vm.serializeUint(key, "spPermissionless_sdBalance", a.spPermissionlessSd);
        vm.serializeUint(
            key,
            "spPermissionless_operatorEthRewardsRemaining",
            a.spPermissionlessOperatorEthRewardsRemaining
        );
        vm.serializeUint(
            key,
            "spPermissionless_operatorSdRewardsRemaining",
            a.spPermissionlessOperatorSdRewardsRemaining
        );
        vm.serializeUint(key, "plp_ethBalance", a.plpEth);
        vm.serializeUint(key, "orc_ethBalance", a.orcEth);
        vm.serializeUint(key, "orc_wethBalance", a.orcWethBalance);
        vm.serializeUint(key, "uwm_ethBalance", a.uwmEth);
        vm.serializeUint(key, "uwm_nextRequestId", a.uwmNextRequestId);
        vm.serializeUint(key, "uwm_nextRequestIdToFinalize", a.uwmNextRequestIdToFinalize);
        vm.serializeUint(
            key,
            "uwm_minBlockDelayToFinalizeWithdrawRequest",
            a.uwmMinBlockDelayToFinalizeWithdrawRequest
        );
        vm.serializeUint(key, "oracle_trustedNodesCount", a.oracleTrustedNodesCount);
        vm.serializeUint(key, "oracle_lastReportedErBlock", a.oracleLastReportedErBlock);
        vm.serializeUint(key, "oracle_lastReportedTotalEth", a.oracleLastReportedTotalEth);
        vm.serializeUint(key, "oracle_lastReportedEthXSupply", a.oracleLastReportedEthXSupply);
        vm.serializeUint(key, "treasury_ethBalance", a.treasuryEth);
        string memory payload = vm.serializeUint(key, "treasury_sdBalance", a.treasurySd);
        vm.writeJson(payload, _snapshotPath(freezeBlock));
    }

    /// @notice Read previously written aggregates from disk.
    function _readSnapshot(uint256 freezeBlock) internal returns (ContractAggregates memory a) {
        string memory raw = vm.readFile(_snapshotPath(freezeBlock));
        a.ethBalance = vm.parseJsonUint(raw, "$.sspm_ethBalance");
        a.ethXTotalSupply = vm.parseJsonUint(raw, "$.sspm_ethXTotalSupply");
        a.sspmExchangeRate = vm.parseJsonUint(raw, "$.sspm_exchangeRate");
        a.sspmTotalAssets = vm.parseJsonUint(raw, "$.sspm_totalAssets");
        a.sspmLastExcessEthDepositBlock = vm.parseJsonUint(raw, "$.sspm_lastExcessEthDepositBlock");
        a.sdupSdBalance = vm.parseJsonUint(raw, "$.sdup_sdBalance");
        a.sdupTotalUtilizedSD = vm.parseJsonUint(raw, "$.sdup_totalUtilizedSD");
        a.sdupCTokenTotalSupply = vm.parseJsonUint(raw, "$.sdup_cTokenTotalSupply");
        a.sdupAccumulatedProtocolFee = vm.parseJsonUint(raw, "$.sdup_accumulatedProtocolFee");
        a.sdupNextRequestId = vm.parseJsonUint(raw, "$.sdup_nextRequestId");
        a.sdupNextRequestIdToFinalize = vm.parseJsonUint(raw, "$.sdup_nextRequestIdToFinalize");
        a.sdupMinBlockDelayToFinalizeRequest = vm.parseJsonUint(raw, "$.sdup_minBlockDelayToFinalizeRequest");
        a.spPermissionedEth = vm.parseJsonUint(raw, "$.spPermissioned_ethBalance");
        a.spPermissionedSd = vm.parseJsonUint(raw, "$.spPermissioned_sdBalance");
        a.spPermissionedOperatorEthRewardsRemaining = vm.parseJsonUint(
            raw,
            "$.spPermissioned_operatorEthRewardsRemaining"
        );
        a.spPermissionedOperatorSdRewardsRemaining = vm.parseJsonUint(
            raw,
            "$.spPermissioned_operatorSdRewardsRemaining"
        );
        a.spPermissionlessEth = vm.parseJsonUint(raw, "$.spPermissionless_ethBalance");
        a.spPermissionlessSd = vm.parseJsonUint(raw, "$.spPermissionless_sdBalance");
        a.spPermissionlessOperatorEthRewardsRemaining = vm.parseJsonUint(
            raw,
            "$.spPermissionless_operatorEthRewardsRemaining"
        );
        a.spPermissionlessOperatorSdRewardsRemaining = vm.parseJsonUint(
            raw,
            "$.spPermissionless_operatorSdRewardsRemaining"
        );
        a.plpEth = vm.parseJsonUint(raw, "$.plp_ethBalance");
        a.orcEth = vm.parseJsonUint(raw, "$.orc_ethBalance");
        a.orcWethBalance = vm.parseJsonUint(raw, "$.orc_wethBalance");
        a.uwmEth = vm.parseJsonUint(raw, "$.uwm_ethBalance");
        a.uwmNextRequestId = vm.parseJsonUint(raw, "$.uwm_nextRequestId");
        a.uwmNextRequestIdToFinalize = vm.parseJsonUint(raw, "$.uwm_nextRequestIdToFinalize");
        a.uwmMinBlockDelayToFinalizeWithdrawRequest = vm.parseJsonUint(
            raw,
            "$.uwm_minBlockDelayToFinalizeWithdrawRequest"
        );
        a.oracleTrustedNodesCount = vm.parseJsonUint(raw, "$.oracle_trustedNodesCount");
        a.oracleLastReportedErBlock = vm.parseJsonUint(raw, "$.oracle_lastReportedErBlock");
        a.oracleLastReportedTotalEth = vm.parseJsonUint(raw, "$.oracle_lastReportedTotalEth");
        a.oracleLastReportedEthXSupply = vm.parseJsonUint(raw, "$.oracle_lastReportedEthXSupply");
        a.treasuryEth = vm.parseJsonUint(raw, "$.treasury_ethBalance");
        a.treasurySd = vm.parseJsonUint(raw, "$.treasury_sdBalance");
    }
}
