// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IOperatorRewardsCollector } from "contracts/interfaces/IOperatorRewardsCollector.sol";
import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";

interface IERC20MinApprove {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @notice Settles every non-responsive operator on the ghost-batch
///         slice of the runoff sheet via a single Safe-style batch.
///         Approves the treasury SD budget, loops
///         `adminSettleOperator` per candidate, captures per-call
///         `gasleft` deltas, and tracks treasury SD + ETH balance
///         deltas per settlement. Enforces EIP-7825 per-tx gas cap
///         (2^24 = 16_777_216): projected Safe `gasLimit` with 20%
///         headroom + wrapper overhead must stay under the cap. Flags
///         any single call above 1.5M. Writes `ghost-batch-gas-report.json`.
contract GhostOperatorSettlementTest is SunsetForkBase {
    uint256 internal constant PER_CALL_REVIEW_GAS = 1_500_000;
    /// @dev EIP-7825 (Fusaka): protocol per-transaction gas cap = 2^24.
    uint256 internal constant MAX_TX_GAS_LIMIT = 16_777_216;
    uint256 internal constant SAFE_WRAPPER_OVERHEAD = 80_000;
    uint256 internal constant GAS_HEADROOM_NUM = 12;
    uint256 internal constant GAS_HEADROOM_DEN = 10;
    /// @dev 5% buffer on the SD approval above the sheet's `Σ interestSd`.
    ///      Covers small accrual between sheet snapshot and the actual
    ///      `adminSettleOperator` call.
    uint256 internal constant SD_BUDGET_BUFFER_BPS = 500;

    struct BatchTotals {
        uint256 cumulativeGas;
        uint256 flaggedCount;
        uint256 settledCount;
        uint256 totalSdSpent;
        uint256 totalEthReceived;
    }

    function setUp() public override {
        super.setUp();
        // Upgrade so adminSettleOperator exists on the live ORC proxy.
        _upgradeAllProxies(_loadSheet());
    }

    function test_GhostBatch() public {
        Sheet memory sheet = _loadSheet();
        require(sheet.ghostBatch.length > 0, "ghost_batch slice empty");

        address sdToken = IStaderConfig(MainnetAddresses.STADER_CONFIG).getStaderToken();
        address treasury = IStaderConfig(MainnetAddresses.STADER_CONFIG).getStaderTreasury();
        uint256 budgetCap = _approveBudget(sheet, sdToken, treasury);

        address managerSafe = _findRoleSafe(sheet, MainnetAddresses.STADER_CONFIG, "MANAGER");
        require(managerSafe != address(0), "manager not in sheet");

        uint256[] memory perCallGas = new uint256[](sheet.ghostBatch.length);
        BatchTotals memory t;

        for (uint256 i = 0; i < sheet.ghostBatch.length; i++) {
            _settleOne(sheet.ghostBatch[i], managerSafe, sdToken, treasury, perCallGas, i, t);
            _assertWithinTxGasCap(t.cumulativeGas, "ghost batch exceeds EIP-7825 tx gas cap at index");
        }

        assertLe(t.totalSdSpent, budgetCap, "aggregate treasury SD spent exceeds budget cap");

        uint256 recommendedSafeGasLimit = _recommendedSafeGasLimit(t.cumulativeGas);
        assertLe(recommendedSafeGasLimit, MAX_TX_GAS_LIMIT, "recommended Safe gasLimit exceeds EIP-7825 cap");
        assertLe(
            t.cumulativeGas + SAFE_WRAPPER_OVERHEAD,
            MAX_TX_GAS_LIMIT,
            "cumulative inner gas + Safe overhead exceeds EIP-7825 cap"
        );
        emit log_named_uint("settledCount", t.settledCount);
        emit log_named_uint("totalSdSpent", t.totalSdSpent);
        emit log_named_uint("totalEthReceived", t.totalEthReceived);
        emit log_named_uint("cumulative gas", t.cumulativeGas);
        emit log_named_uint("recommended Safe gasLimit", recommendedSafeGasLimit);
        emit log_named_uint("flagged calls (>1.5M)", t.flaggedCount);

        _writeGasReport(
            sheet,
            perCallGas,
            t.cumulativeGas,
            recommendedSafeGasLimit,
            t.flaggedCount,
            t.settledCount,
            t.totalSdSpent
        );
    }

    function _approveBudget(Sheet memory sheet, address sdToken, address treasury) private returns (uint256) {
        uint256 totalInterest;
        for (uint256 i = 0; i < sheet.ghostBatch.length; i++) totalInterest += sheet.ghostBatch[i].interestSd;
        uint256 budgetCap = totalInterest + (totalInterest * SD_BUDGET_BUFFER_BPS) / 10_000;
        emit log_named_uint("ghost batch size", sheet.ghostBatch.length);
        emit log_named_uint("total interest SD (wei)", totalInterest);
        emit log_named_uint("budget cap (wei)", budgetCap);
        vm.prank(treasury);
        IERC20MinApprove(sdToken).approve(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, budgetCap);
        return budgetCap;
    }

    function _settleOne(
        GhostBatchRow memory row,
        address managerSafe,
        address sdToken,
        address treasury,
        uint256[] memory perCallGas,
        uint256 i,
        BatchTotals memory t
    ) private {
        uint256 preSd = IERC20MinApprove(sdToken).balanceOf(treasury);
        uint256 preEth = treasury.balance;

        uint256 before = gasleft();
        vm.prank(managerSafe);
        (bool success, ) = MainnetAddresses.OPERATOR_REWARDS_COLLECTOR.call(
            abi.encodeWithSelector(IOperatorRewardsCollector.adminSettleOperator.selector, row.addr)
        );
        perCallGas[i] = before - gasleft();
        t.cumulativeGas += perCallGas[i];

        if (success) {
            t.settledCount++;
            uint256 sdSpent = preSd > IERC20MinApprove(sdToken).balanceOf(treasury)
                ? preSd - IERC20MinApprove(sdToken).balanceOf(treasury)
                : 0;
            uint256 ethReceived = treasury.balance > preEth ? treasury.balance - preEth : 0;
            t.totalSdSpent += sdSpent;
            t.totalEthReceived += ethReceived;
            emit log_named_address("settled operator", row.addr);
            emit log_named_uint("  treasury SD spent", sdSpent);
            emit log_named_uint("  treasury ETH received", ethReceived);
            assertLe(sdSpent, row.interestSd + 1, "per-call treasury SD spent exceeds candidate's interestSd");
        } else {
            emit log_named_address("adminSettleOperator reverted for", row.addr);
        }

        if (perCallGas[i] > PER_CALL_REVIEW_GAS) {
            t.flaggedCount++;
            emit log_named_uint("FLAG: per-call gas > 1.5M at index", i);
        }
    }

    function _writeGasReport(
        Sheet memory sheet,
        uint256[] memory perCallGas,
        uint256 cumulativeGas,
        uint256 recommendedSafeGasLimit,
        uint256 flaggedCount,
        uint256 settledCount,
        uint256 totalSdSpent
    ) private {
        string memory root = "ghostBatchGas";
        for (uint256 i = 0; i < sheet.ghostBatch.length; i++) {
            string memory rowKey = string.concat("call", vm.toString(i));
            vm.serializeAddress(rowKey, "address", sheet.ghostBatch[i].addr);
            string memory rowJson = vm.serializeUint(rowKey, "gasUsed", perCallGas[i]);
            vm.serializeString(root, string.concat("perCall_", vm.toString(i)), rowJson);
        }
        vm.serializeUint(root, "cumulativeGasUsed", cumulativeGas);
        vm.serializeUint(root, "cumulativeWithSafeOverhead", cumulativeGas + SAFE_WRAPPER_OVERHEAD);
        vm.serializeUint(root, "maxTxGasLimit", MAX_TX_GAS_LIMIT);
        vm.serializeUint(root, "maxInnerGasWithHeadroom", _maxInnerGasWithHeadroom());
        vm.serializeBool(root, "withinProtocolCap", recommendedSafeGasLimit <= MAX_TX_GAS_LIMIT);
        vm.serializeUint(root, "recommendedSafeGasLimit", recommendedSafeGasLimit);
        vm.serializeUint(root, "flaggedCalls", flaggedCount);
        vm.serializeUint(root, "settledCount", settledCount);
        string memory payload = vm.serializeUint(root, "totalSdSpent", totalSdSpent);
        vm.writeJson(payload, "./test/fork/sunset/snapshots/ghost-batch-gas-report.json");
    }

    function _recommendedSafeGasLimit(uint256 cumulativeGas) private pure returns (uint256) {
        return (cumulativeGas * GAS_HEADROOM_NUM) / GAS_HEADROOM_DEN + SAFE_WRAPPER_OVERHEAD;
    }

    /// @dev Largest inner cumulative gas such that `_recommendedSafeGasLimit` <= `MAX_TX_GAS_LIMIT`.
    function _maxInnerGasWithHeadroom() private pure returns (uint256) {
        return ((MAX_TX_GAS_LIMIT - SAFE_WRAPPER_OVERHEAD) * GAS_HEADROOM_DEN) / GAS_HEADROOM_NUM;
    }

    function _assertWithinTxGasCap(uint256 cumulativeGas, string memory err) private {
        assertLe(_recommendedSafeGasLimit(cumulativeGas), MAX_TX_GAS_LIMIT, err);
        assertLe(cumulativeGas + SAFE_WRAPPER_OVERHEAD, MAX_TX_GAS_LIMIT, err);
    }
}
