// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";
import { SnapshotJson } from "./helpers/SnapshotJson.sol";

import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";
import { IStaderOracle, ExchangeRate } from "contracts/interfaces/IStaderOracle.sol";

interface ISSPMRead {
    function getExchangeRate() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function lastExcessETHDepositBlock() external view returns (uint256);
}

interface ISDUPRead {
    function totalUtilizedSD() external view returns (uint256);
    function cTokenTotalSupply() external view returns (uint256);
    function accumulatedProtocolFee() external view returns (uint256);
    function nextRequestId() external view returns (uint256);
    function nextRequestIdToFinalize() external view returns (uint256);
    function minBlockDelayToFinalizeRequest() external view returns (uint256);
}

interface ISPRead {
    function totalOperatorETHRewardsRemaining() external view returns (uint256);
    function totalOperatorSDRewardsRemaining() external view returns (uint256);
}

interface IUWMRead {
    function nextRequestId() external view returns (uint256);
    function nextRequestIdToFinalize() external view returns (uint256);
}

interface IERC20Min {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

/// @notice Read-only capture of freeze-block aggregate state across
///         every contract touched by the runoff. Writes
///         `test/fork/sunset/snapshots/freeze-snapshot-<block>.json`
///         for later assertions to diff against. No upgrades, no
///         impersonation, no mutation.
contract FreezeBlockSnapshotTest is SunsetForkBase, SnapshotJson {
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function test_CaptureFreezeSnapshot() public {
        IStaderConfig config = IStaderConfig(MainnetAddresses.STADER_CONFIG);
        address sdToken = config.getStaderToken();
        address treasury = config.getStaderTreasury();

        ContractAggregates memory a;

        // SSPM.
        a.ethBalance = MainnetAddresses.SSPM.balance;
        a.ethXTotalSupply = IERC20Min(MainnetAddresses.ETHX).totalSupply();
        a.sspmExchangeRate = ISSPMRead(MainnetAddresses.SSPM).getExchangeRate();
        a.sspmTotalAssets = ISSPMRead(MainnetAddresses.SSPM).totalAssets();
        a.sspmLastExcessEthDepositBlock = ISSPMRead(MainnetAddresses.SSPM).lastExcessETHDepositBlock();

        // SDUtilityPool.
        a.sdupSdBalance = IERC20Min(sdToken).balanceOf(MainnetAddresses.SD_UTILITY_POOL);
        a.sdupTotalUtilizedSD = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL).totalUtilizedSD();
        a.sdupCTokenTotalSupply = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL).cTokenTotalSupply();
        a.sdupAccumulatedProtocolFee = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL).accumulatedProtocolFee();
        a.sdupNextRequestId = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL).nextRequestId();
        a.sdupNextRequestIdToFinalize = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL).nextRequestIdToFinalize();
        a.sdupMinBlockDelayToFinalizeRequest = ISDUPRead(MainnetAddresses.SD_UTILITY_POOL)
            .minBlockDelayToFinalizeRequest();

        // SocializingPools.
        a.spPermissionedEth = MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED.balance;
        a.spPermissionedSd = IERC20Min(sdToken).balanceOf(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED);
        a.spPermissionedOperatorEthRewardsRemaining = ISPRead(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED)
            .totalOperatorETHRewardsRemaining();
        a.spPermissionedOperatorSdRewardsRemaining = ISPRead(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED)
            .totalOperatorSDRewardsRemaining();
        a.spPermissionlessEth = MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS.balance;
        a.spPermissionlessSd = IERC20Min(sdToken).balanceOf(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS);
        a.spPermissionlessOperatorEthRewardsRemaining = ISPRead(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS)
            .totalOperatorETHRewardsRemaining();
        a.spPermissionlessOperatorSdRewardsRemaining = ISPRead(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS)
            .totalOperatorSDRewardsRemaining();

        // PermissionlessPool, ORC, UWM.
        a.plpEth = MainnetAddresses.PERMISSIONLESS_POOL.balance;
        a.orcEth = MainnetAddresses.OPERATOR_REWARDS_COLLECTOR.balance;
        a.orcWethBalance = IERC20Min(MAINNET_WETH).balanceOf(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR);
        a.uwmEth = MainnetAddresses.USER_WITHDRAWAL_MANAGER.balance;
        a.uwmNextRequestId = IUWMRead(MainnetAddresses.USER_WITHDRAWAL_MANAGER).nextRequestId();
        a.uwmNextRequestIdToFinalize = IUWMRead(MainnetAddresses.USER_WITHDRAWAL_MANAGER).nextRequestIdToFinalize();
        a.uwmMinBlockDelayToFinalizeWithdrawRequest = config.getMinBlockDelayToFinalizeWithdrawRequest();

        // StaderOracle aggregate state + the canonical last-reported
        // exchange rate that downstream redemption checks reference.
        IStaderOracle oracle = IStaderOracle(MainnetAddresses.STADER_ORACLE);
        a.oracleTrustedNodesCount = oracle.trustedNodesCount();
        ExchangeRate memory er = oracle.getExchangeRate();
        a.oracleLastReportedErBlock = er.reportingBlockNumber;
        a.oracleLastReportedTotalEth = er.totalETHBalance;
        a.oracleLastReportedEthXSupply = er.totalETHXSupply;

        // Treasury.
        a.treasuryEth = treasury.balance;
        a.treasurySd = IERC20Min(sdToken).balanceOf(treasury);

        Sheet memory sheet = _loadSheet();
        _writeSnapshot(freezeBlock, block.timestamp, sheet.custody.custody, a);

        emit log_named_uint("freezeBlock", freezeBlock);
        emit log_named_uint("ETHx totalSupply (wei)", a.ethXTotalSupply);
        emit log_named_uint("SSPM ETH balance (wei)", a.ethBalance);
        emit log_named_uint("SDUtilityPool SD balance (wei)", a.sdupSdBalance);
        emit log_named_uint("Oracle trusted nodes", a.oracleTrustedNodesCount);
        emit log_named_uint("Oracle last reported ER block", a.oracleLastReportedErBlock);
        emit log_named_uint("ORC WETH balance (wei)", a.orcWethBalance);
        emit log_named_uint("UWM nextRequestId", a.uwmNextRequestId);
    }
}
