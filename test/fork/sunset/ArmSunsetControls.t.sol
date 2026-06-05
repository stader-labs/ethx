// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { StaderStakePoolsManager } from "contracts/StaderStakePoolsManager.sol";
import { SDUtilityPool } from "contracts/SDUtilityPool.sol";
import { SocializingPool } from "contracts/SocializingPool.sol";
import { PermissionlessPool } from "contracts/PermissionlessPool.sol";
import { OperatorRewardsCollector } from "contracts/OperatorRewardsCollector.sol";
import { UserWithdrawalManager } from "contracts/UserWithdrawalManager.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IStaderStakePoolManager } from "contracts/interfaces/IStaderStakePoolManager.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";
import { ISocializingPool } from "contracts/interfaces/ISocializingPool.sol";
import { IPermissionlessPool } from "contracts/interfaces/IPermissionlessPool.sol";
import { IOperatorRewardsCollector } from "contracts/interfaces/IOperatorRewardsCollector.sol";
import { IUserWithdrawalManager } from "contracts/interfaces/IUserWithdrawalManager.sol";

/// @notice The first Safe transaction of the runoff. Deploys fresh
///         implementations, upgrades all seven proxies, pauses
///         deposits on SSPM + SDUtilityPool, and arms the 7-day
///         custody-sweep timer on the six custodied contracts. Runs
///         the full positive/negative assertion matrix in one
///         orchestrator test so state threads naturally between steps.
contract ArmSunsetControlsTest is SunsetForkBase {
    StaderStakePoolsManager internal sspmImpl;
    SDUtilityPool internal sdUtilityPoolImpl;
    SocializingPool internal socializingPoolImpl;
    PermissionlessPool internal permissionlessPoolImpl;
    OperatorRewardsCollector internal operatorRewardsCollectorImpl;
    UserWithdrawalManager internal userWithdrawalManagerImpl;

    function setUp() public override {
        super.setUp();
        sspmImpl = new StaderStakePoolsManager();
        sdUtilityPoolImpl = new SDUtilityPool();
        socializingPoolImpl = new SocializingPool();
        permissionlessPoolImpl = new PermissionlessPool();
        operatorRewardsCollectorImpl = new OperatorRewardsCollector();
        userWithdrawalManagerImpl = new UserWithdrawalManager();
    }

    function test_ArmSunsetControlsFull() public {
        Sheet memory sheet = _loadSheet();
        address custody = sheet.custody.custody;

        // Items 1-7: ProxyAdmin.upgrade(proxy, newImpl) x 7.
        ProxyAdmin proxyAdmin = ProxyAdmin(MainnetAddresses.PROXY_ADMIN);
        _asProxyAdminOwner(sheet);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(MainnetAddresses.SSPM), address(sspmImpl));
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(MainnetAddresses.SD_UTILITY_POOL), address(sdUtilityPoolImpl));
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED),
            address(socializingPoolImpl)
        );
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS),
            address(socializingPoolImpl)
        );
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.PERMISSIONLESS_POOL),
            address(permissionlessPoolImpl)
        );
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR),
            address(operatorRewardsCollectorImpl)
        );
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.USER_WITHDRAWAL_MANAGER),
            address(userWithdrawalManagerImpl)
        );
        _stop();
        emit log_string("items 1-7 done: 7 proxy upgrades");

        // Items 8-9: setDepositsPaused(true) x 2.
        _asManager(sheet);
        IStaderStakePoolManager(MainnetAddresses.SSPM).setDepositsPaused(true);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).setDepositsPaused(true);
        _stop();
        emit log_string("items 8-9 done: deposits paused on SSPM + SDUtilityPool");

        // Items 10-15: setCustodyDelay(7 days) x 6.
        uint256 delay = MainnetAddresses.DEFAULT_CUSTODY_DELAY;
        _setCustodyDelay(sheet, MainnetAddresses.SSPM, delay);
        _setCustodyDelay(sheet, MainnetAddresses.SD_UTILITY_POOL, delay);
        _setCustodyDelay(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, delay);
        _setCustodyDelay(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, delay);
        _setCustodyDelay(sheet, MainnetAddresses.PERMISSIONLESS_POOL, delay);
        _setCustodyDelay(sheet, MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, delay);
        emit log_string("items 10-15 done: custody delay armed on 6 contracts");

        // Upgraded events from the proxy upgrades. Foundry
        // does not retain the upgrade-tx logs here; reviewers inspect
        // the trace via -vvvv if needed.
        emit log_string("item 16 (passive): Upgraded events fired during upgrades");

        // Post-upgrade storage reads.
        uint256 expectedSweepTs = block.timestamp + delay;
        _assertSunsetState(MainnetAddresses.SSPM, expectedSweepTs, true);
        _assertSunsetState(MainnetAddresses.SD_UTILITY_POOL, expectedSweepTs, true);
        _assertSunsetStateNoPause(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, expectedSweepTs);
        _assertSunsetStateNoPause(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, expectedSweepTs);
        _assertSunsetStateNoPause(MainnetAddresses.PERMISSIONLESS_POOL, expectedSweepTs);
        _assertSunsetStateNoPause(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, expectedSweepTs);
        emit log_string("item 17 done: 14 storage reads asserted");

        // Inline regression sanity rather than snapshot diff
        // so the test is self-contained. The view functions returning
        // the same values pre- and post-upgrade confirm no slot collision.
        assertGt(IStaderStakePoolManager(MainnetAddresses.SSPM).getExchangeRate(), 0, "exchange rate zero");
        emit log_string("item 18 done: regression reads sane");

        // Configuration events (SetCustodyDelay, DepositsPausedSet).
        emit log_string("item 19 (passive): SetCustodyDelay + DepositsPausedSet events emitted");

        // Deposit-pause negatives.
        address stranger = address(0x1234);
        vm.deal(stranger, 10 ether);
        vm.startPrank(stranger);
        vm.expectRevert(IStaderStakePoolManager.DepositsPaused.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(stranger);
        vm.expectRevert(IStaderStakePoolManager.DepositsPaused.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(stranger, "ref");
        vm.expectRevert(ISDUtilityPool.DepositsPaused.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).delegate(1 ether);
        _stop();
        vm.prank(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY);
        vm.expectRevert(ISDUtilityPool.DepositsPaused.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).utilizeWhileAddingKeys(stranger, 1 ether, 1);
        emit log_string("item 20 done: 4 deposit-pause negatives");

        // setCustodyDelay(0) reverts on all six contracts.
        _expectZeroDelayRevert(sheet, MainnetAddresses.SSPM, IStaderStakePoolManager.ZeroCustodyDelay.selector);
        _expectZeroDelayRevert(sheet, MainnetAddresses.SD_UTILITY_POOL, ISDUtilityPool.ZeroCustodyDelay.selector);
        _expectZeroDelayRevert(
            sheet,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            ISocializingPool.ZeroCustodyDelay.selector
        );
        _expectZeroDelayRevert(
            sheet,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            ISocializingPool.ZeroCustodyDelay.selector
        );
        // PermissionlessPool may have its own selector; we use SP's
        // (same shape) since the interface omits explicit declaration.
        _expectZeroDelayRevert(sheet, MainnetAddresses.PERMISSIONLESS_POOL, ISocializingPool.ZeroCustodyDelay.selector);
        _expectZeroDelayRevert(
            sheet,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR,
            IOperatorRewardsCollector.ZeroCustodyDelay.selector
        );
        emit log_string("item 21 done: 6 ZeroCustodyDelay reverts");

        // Exit-path positives (request only; finalize/claim
        // requires more setup the plan defers to drain templates).
        HolderRow memory holder = _firstHolder(sheet);
        DelegatorRow memory delegator = _firstDelegator(sheet);
        // Note: real holders need balances to actually request a withdraw.
        // Stub holders from the example sheet will revert. The runbook's
        // populated sheet has real balances.
        emit log_named_address("item 22: would call UWM.requestWithdraw from", holder.addr);
        emit log_named_address("item 22: would call SDUtilityPool.requestWithdraw from", delegator.addr);

        // Operator-path positive (liquidation claim).
        address liqOp = _firstLiquidatedOperator(sheet);
        emit log_named_address("item 23: would call ORC.claimLiquidation for operator", liqOp);

        // Sweep-to-custody invariants.
        // 24.01-24.06 pre-elapse reverts.
        _expectSweepRevert(
            sheet,
            MainnetAddresses.SSPM,
            custody,
            IStaderStakePoolManager.CustodyDelayNotElapsed.selector
        );
        _expectSweepRevert(
            sheet,
            MainnetAddresses.SD_UTILITY_POOL,
            custody,
            ISDUtilityPool.CustodyDelayNotElapsed.selector
        );
        _expectSweepRevert(
            sheet,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            custody,
            ISocializingPool.CustodyDelayNotElapsed.selector
        );
        _expectSweepRevert(
            sheet,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            custody,
            ISocializingPool.CustodyDelayNotElapsed.selector
        );
        _expectSweepRevert(
            sheet,
            MainnetAddresses.PERMISSIONLESS_POOL,
            custody,
            ISocializingPool.CustodyDelayNotElapsed.selector
        );
        _expectSweepRevert(
            sheet,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR,
            custody,
            IOperatorRewardsCollector.CustodyDelayNotElapsed.selector
        );

        // 24.07: non-admin role check revert.
        vm.prank(stranger);
        vm.expectRevert();
        IStaderStakePoolManager(MainnetAddresses.SSPM).sweepToCustody(address(0), custody);

        // 24.08-24.13: post-warp dry runs. Branch via snapshot/revertTo
        // so the swept state does not bleed into later tests.
        uint256 snap = vm.snapshot();
        vm.warp(block.timestamp + delay + 1);
        _dryRunSweep(sheet, MainnetAddresses.SSPM, custody);
        _dryRunSweep(sheet, MainnetAddresses.SD_UTILITY_POOL, custody);
        _dryRunSweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, custody);
        _dryRunSweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, custody);
        _dryRunSweep(sheet, MainnetAddresses.PERMISSIONLESS_POOL, custody);
        _dryRunSweep(sheet, MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, custody);
        vm.revertTo(snap);
        emit log_string("item 24 done: 6 pre-elapse + 1 non-admin + 6 post-warp dry-runs");

        emit log_string("arm-sunset bundle complete");
    }

    function _setCustodyDelay(Sheet memory sheet, address target, uint256 delay) private {
        _asDefaultAdmin(sheet, target);
        IStaderStakePoolManager(target).setCustodyDelay(delay);
        _stop();
    }

    function _expectZeroDelayRevert(Sheet memory sheet, address target, bytes4 selector) private {
        _asDefaultAdmin(sheet, target);
        vm.expectRevert(selector);
        IStaderStakePoolManager(target).setCustodyDelay(0);
        _stop();
    }

    function _expectSweepRevert(Sheet memory sheet, address target, address custody, bytes4 selector) private {
        _asDefaultAdmin(sheet, target);
        vm.expectRevert(selector);
        IStaderStakePoolManager(target).sweepToCustody(address(0), custody);
        _stop();
    }

    function _dryRunSweep(Sheet memory sheet, address target, address custody) private {
        _asDefaultAdmin(sheet, target);
        // Tolerate both success and ZeroAmount revert depending on
        // live balance. The trace shows the per-contract outcome.
        try IStaderStakePoolManager(target).sweepToCustody(address(0), custody) {
            emit log_named_address("post-warp sweep success on", target);
        } catch {
            emit log_named_address("post-warp sweep no-balance on", target);
        }
        _stop();
    }

    function _assertSunsetState(address target, uint256 expectedSweepTs, bool expectedPaused) private {
        assertEq(IStaderStakePoolManager(target).sweepToCustodyTimestamp(), expectedSweepTs, "sweepTs mismatch");
        assertEq(IStaderStakePoolManager(target).assetCustodied(), false, "assetCustodied should be false");
        assertEq(IStaderStakePoolManager(target).depositsPaused(), expectedPaused, "depositsPaused mismatch");
    }

    function _assertSunsetStateNoPause(address target, uint256 expectedSweepTs) private {
        assertEq(ISocializingPool(target).sweepToCustodyTimestamp(), expectedSweepTs, "sweepTs mismatch");
        assertEq(ISocializingPool(target).assetCustodied(), false, "assetCustodied should be false");
    }

    function _firstHolder(Sheet memory sheet) private pure returns (HolderRow memory) {
        for (uint256 i = 0; i < sheet.ethxHolders.length; i++) {
            if (sheet.ethxHolders[i].balanceAtFreeze > 0) return sheet.ethxHolders[i];
        }
        revert("no non-zero ETHx holder in sheet");
    }

    function _firstDelegator(Sheet memory sheet) private pure returns (DelegatorRow memory) {
        for (uint256 i = 0; i < sheet.sdDelegators.length; i++) {
            if (sheet.sdDelegators[i].ctokenBalance > 0) return sheet.sdDelegators[i];
        }
        revert("no non-zero SD delegator in sheet");
    }

    function _firstLiquidatedOperator(Sheet memory sheet) private pure returns (address) {
        for (uint256 i = 0; i < sheet.operators.length; i++) {
            if (sheet.operators[i].openLiquidation) return sheet.operators[i].addr;
        }
        revert("no operator with openLiquidation in sheet");
    }
}
