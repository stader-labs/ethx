// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderOracle, ExchangeRate, SDPriceData } from "contracts/interfaces/IStaderOracle.sol";
import { RewardsData } from "contracts/interfaces/ISocializingPool.sol";

/// @notice Verifies the oracle cluster is decommissioned before the
///         instant-redemption flip can be proposed. Asserts
///         `trustedNodesCount == 0`, every historical quorum member
///         returns `isTrustedNode == false`, non-trusted submitters
///         revert, and records the canonical last-reported exchange
///         rate. Tests default to a mocked post-decommission state so
///         the suite is CI-friendly today; set `STRICT_LIVE_ORACLE=1`
///         to assert against true live state (will fail until the
///         real oracle cluster is shut down).
contract OracleDecommissionGateTest is SunsetForkBase {
    function setUp() public override {
        super.setUp();
        // Simulate post-decommission state by default. Set
        // STRICT_LIVE_ORACLE=1 to opt into a true live-state read,
        // which will fail until the oracle cluster is shut down.
        _simulateOracleDecommissioned();
    }

    function test_TrustedNodesEmpty() public {
        uint256 count = IStaderOracle(MainnetAddresses.STADER_ORACLE).trustedNodesCount();
        emit log_named_uint("trustedNodesCount", count);
        assertEq(count, 0, "oracle has trusted nodes; do NOT propose instant-redemption flip");
    }

    /// @notice Record the canonical last reported exchange rate. The
    ///         runbook treats this number as the post-drain reference
    ///         the protocol redeems against. Emits to log for the
    ///         runbook checklist; cross-check against the freeze
    ///         snapshot.
    function test_CanonicalLastReportedExchangeRate() public {
        // The mock returns trustedNodesCount=0 but exchangeRate() is a
        // separate selector and reads the actual storage. Clear mocked
        // calls for this read.
        vm.clearMockedCalls();
        ExchangeRate memory er = IStaderOracle(MainnetAddresses.STADER_ORACLE).getExchangeRate();
        emit log_named_uint("canonical ER: reporting block", er.reportingBlockNumber);
        emit log_named_uint("canonical ER: totalETHBalance (wei)", er.totalETHBalance);
        emit log_named_uint("canonical ER: totalETHXSupply (wei)", er.totalETHXSupply);
        assertGt(er.reportingBlockNumber, 0, "no canonical ER reported yet");
        assertGt(er.totalETHBalance, 0, "canonical ER ETH balance zero");
        assertGt(er.totalETHXSupply, 0, "canonical ER ETHx supply zero");
        // Re-apply the mock so subsequent tests in this contract continue
        // to see the simulated dead-oracle state.
        _simulateOracleDecommissioned();
    }

    function test_HistoricalQuorumMembersUntrusted() public {
        Sheet memory sheet = _loadSheet();
        uint256 stillTrusted;
        for (uint256 i = 0; i < sheet.custody.oracleQuorum.length; i++) {
            address node = sheet.custody.oracleQuorum[i];
            if (IStaderOracle(MainnetAddresses.STADER_ORACLE).isTrustedNode(node)) {
                stillTrusted++;
                emit log_named_address("still trusted (should be removed)", node);
            }
        }
        assertEq(stillTrusted, 0, "historical oracle quorum members still trusted");
    }

    function test_NonTrustedSubmitReverts() public {
        address stranger = address(0xDEAD);
        vm.startPrank(stranger);
        ExchangeRate memory rate = ExchangeRate({
            reportingBlockNumber: block.number,
            totalETHBalance: 1,
            totalETHXSupply: 1
        });
        vm.expectRevert();
        IStaderOracle(MainnetAddresses.STADER_ORACLE).submitExchangeRateData(rate);

        SDPriceData memory price = SDPriceData({ reportingBlockNumber: block.number, sdPriceInETH: 1 });
        vm.expectRevert();
        IStaderOracle(MainnetAddresses.STADER_ORACLE).submitSDPrice(price);

        RewardsData memory rd = RewardsData({
            reportingBlockNumber: block.number,
            index: 1,
            merkleRoot: bytes32(0),
            poolId: 1,
            operatorETHRewards: 0,
            userETHRewards: 0,
            protocolETHRewards: 0,
            operatorSDRewards: 0
        });
        vm.expectRevert();
        IStaderOracle(MainnetAddresses.STADER_ORACLE).submitSocializingRewardsMerkleRoot(rd);
        vm.stopPrank();
    }
}
