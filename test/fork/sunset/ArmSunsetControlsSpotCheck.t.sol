// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderStakePoolManager } from "contracts/interfaces/IStaderStakePoolManager.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";
import { ISocializingPool } from "contracts/interfaces/ISocializingPool.sol";
import { IOperatorRewardsCollector } from "contracts/interfaces/IOperatorRewardsCollector.sol";

/// @notice Day-of-execute spot check that catches state drift between
///         Safe propose and execute. Mirrors the post-upgrade
///         assertion matrix from `ArmSunsetControls` against the
///         execute-block fork without re-running the upgrade + pause
///         + arm calls themselves.
///
///         Auto-detects whether the arm-sunset transaction has already
///         landed on the live fork by reading `SSPM.depositsPaused()`.
///         If not landed, the test self-upgrades + arms locally (same
///         implementations the runbook ships) so the spot check
///         exercises real post-arm behaviour against the freshly
///         captured fork.
contract ArmSunsetControlsSpotCheckTest is SunsetForkBase {
    bool internal sunsetArmed;

    function setUp() public override {
        super.setUp();
        Sheet memory sheet = _loadSheet();

        // Detect live arm-sunset state. If sweep already happened, abort
        // (spot check is meaningless post-sweep).
        try IStaderStakePoolManager(MainnetAddresses.SSPM).assetCustodied() returns (bool custodied) {
            if (custodied) {
                emit log_string("CRITICAL: SSPM.assetCustodied already true. Sweep landed. Abort.");
                revert("post-sweep state; spot check not applicable");
            }
            sunsetArmed = IStaderStakePoolManager(MainnetAddresses.SSPM).depositsPaused();
        } catch {
            sunsetArmed = false;
        }

        if (!sunsetArmed) {
            emit log_string(
                "Arm-sunset transaction not yet on live fork; self-upgrade + arm so spot check matrix can run."
            );
            _upgradeAllProxies(sheet);
            _armSunsetLocally(sheet);
        }
    }

    function _armSunsetLocally(Sheet memory sheet) private {
        // Set deposits paused on SSPM + SDUtilityPool.
        address manager = _asManager(sheet);
        IStaderStakePoolManager(MainnetAddresses.SSPM).setDepositsPaused(true);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).setDepositsPaused(true);
        _stop();
        manager;
        // Arm custody delay on all 6.
        uint256 delay = MainnetAddresses.DEFAULT_CUSTODY_DELAY;
        address[6] memory targets = [
            MainnetAddresses.SSPM,
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR
        ];
        for (uint256 i = 0; i < targets.length; i++) {
            _asDefaultAdmin(sheet, targets[i]);
            IStaderStakePoolManager(targets[i]).setCustodyDelay(delay);
            _stop();
        }
    }

    /// @notice post-upgrade storage reads return expected values
    ///         on every upgraded contract.
    function test_Item17_StorageState() public {
        address[6] memory targets = [
            MainnetAddresses.SSPM,
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR
        ];
        for (uint256 i = 0; i < targets.length; i++) {
            assertGt(
                IStaderStakePoolManager(targets[i]).sweepToCustodyTimestamp(),
                block.timestamp,
                "sweepTs not in the future"
            );
            assertFalse(IStaderStakePoolManager(targets[i]).assetCustodied(), "assetCustodied should be false");
        }
        assertTrue(IStaderStakePoolManager(MainnetAddresses.SSPM).depositsPaused(), "SSPM not paused");
        assertTrue(IStaderStakePoolManager(MainnetAddresses.SD_UTILITY_POOL).depositsPaused(), "SDUP not paused");
    }

    /// @notice regression view-function reads return non-zero
    ///         (sanity check; full snapshot diff is captured by FreezeBlockSnapshot).
    function test_Item18_RegressionReads() public {
        assertGt(IStaderStakePoolManager(MainnetAddresses.SSPM).getExchangeRate(), 0, "exchange rate zero");
        // cTokenTotalSupply uses an extended interface; cast via low-level
        // call to avoid pulling in the full ISDUP at the top.
        (bool ok, bytes memory d) = MainnetAddresses.SD_UTILITY_POOL.staticcall(
            abi.encodeWithSignature("cTokenTotalSupply()")
        );
        require(ok && d.length >= 32, "cTokenTotalSupply read failed");
        assertGt(abi.decode(d, (uint256)), 0, "cTokenTotalSupply zero");
    }

    /// @notice four deposit-pause negatives.
    function test_Item20_DepositPauseNegatives() public {
        address stranger = address(0x1234);
        vm.deal(stranger, 10 ether);
        vm.prank(stranger);
        vm.expectRevert(IStaderStakePoolManager.DepositsPaused.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(stranger);

        vm.prank(stranger);
        vm.expectRevert(IStaderStakePoolManager.DepositsPaused.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(stranger, "ref");

        vm.prank(stranger);
        vm.expectRevert(ISDUtilityPool.DepositsPaused.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).delegate(1 ether);

        vm.prank(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY);
        vm.expectRevert(ISDUtilityPool.DepositsPaused.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).utilizeWhileAddingKeys(stranger, 1 ether, 1);
    }

    /// @notice setCustodyDelay(0) reverts on all six contracts.
    function test_Item21_ZeroCustodyDelayReverts() public {
        Sheet memory sheet = _loadSheet();
        address[6] memory targets = [
            MainnetAddresses.SSPM,
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR
        ];
        bytes4[6] memory selectors = [
            IStaderStakePoolManager.ZeroCustodyDelay.selector,
            ISDUtilityPool.ZeroCustodyDelay.selector,
            ISocializingPool.ZeroCustodyDelay.selector,
            ISocializingPool.ZeroCustodyDelay.selector,
            ISocializingPool.ZeroCustodyDelay.selector,
            IOperatorRewardsCollector.ZeroCustodyDelay.selector
        ];
        for (uint256 i = 0; i < targets.length; i++) {
            _asDefaultAdmin(sheet, targets[i]);
            vm.expectRevert(selectors[i]);
            IStaderStakePoolManager(targets[i]).setCustodyDelay(0);
            _stop();
        }
    }

    /// @notice sweep-to-custody invariants.
    function test_Item24_SweepInvariants() public {
        Sheet memory sheet = _loadSheet();
        address custody = sheet.custody.custody;
        address[6] memory targets = [
            MainnetAddresses.SSPM,
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR
        ];
        bytes4[6] memory selectors = [
            IStaderStakePoolManager.CustodyDelayNotElapsed.selector,
            ISDUtilityPool.CustodyDelayNotElapsed.selector,
            ISocializingPool.CustodyDelayNotElapsed.selector,
            ISocializingPool.CustodyDelayNotElapsed.selector,
            ISocializingPool.CustodyDelayNotElapsed.selector,
            IOperatorRewardsCollector.CustodyDelayNotElapsed.selector
        ];

        // Pre-elapse reverts on all six.
        for (uint256 i = 0; i < targets.length; i++) {
            _asDefaultAdmin(sheet, targets[i]);
            vm.expectRevert(selectors[i]);
            IStaderStakePoolManager(targets[i]).sweepToCustody(address(0), custody);
            _stop();
        }

        // Non-admin role-check revert.
        address stranger = address(0x1234);
        vm.prank(stranger);
        vm.expectRevert();
        IStaderStakePoolManager(MainnetAddresses.SSPM).sweepToCustody(address(0), custody);
    }
}
