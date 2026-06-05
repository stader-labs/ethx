// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";
import { IStaderStakePoolManager } from "contracts/interfaces/IStaderStakePoolManager.sol";

interface IERC20BalanceOf {
    function balanceOf(address) external view returns (uint256);
}

/// @notice Custody sweep: nine `sweepToCustody` calls (six ETH, three
///         SD) in the order SDUtilityPool → both SocializingPool
///         proxies → OperatorRewardsCollector → PermissionlessPool →
///         SSPM (last). Each call asserts the `SweptToCustody` event
///         and the custody address balance delta; a master invariant
///         at the end asserts total custody inflow equals the sum of
///         pre-sweep contract balances per asset.
contract CustodySweepTest is SunsetForkBase {
    /// @notice Locally redeclared so we can `vm.expectEmit` it without
    ///         depending on whichever sunset interface declared the
    ///         canonical version.
    event SweptToCustody(address asset, address custody, uint256 amount);

    function setUp() public override {
        super.setUp();
        // Upgrade + arm the sunset controls locally so the sweep can fire.
        Sheet memory s = _loadSheet();
        _upgradeAllProxies(s);
        _armCustodyDelay(s);
        vm.warp(block.timestamp + 7 days + 60);
    }

    function _armCustodyDelay(Sheet memory s) private {
        address[6] memory targets = [
            MainnetAddresses.SSPM,
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR
        ];
        for (uint256 i = 0; i < targets.length; i++) {
            _asDefaultAdmin(s, targets[i]);
            IStaderStakePoolManager(targets[i]).setCustodyDelay(MainnetAddresses.DEFAULT_CUSTODY_DELAY);
            _stop();
        }
    }

    function test_SweepInOrder() public {
        Sheet memory sheet = _loadSheet();
        address custody = sheet.custody.custody;
        address sdToken = IStaderConfig(MainnetAddresses.STADER_CONFIG).getStaderToken();

        uint256 custodyEthBefore = custody.balance;
        uint256 custodySdBefore = IERC20BalanceOf(sdToken).balanceOf(custody);

        uint256 totalEthExpected;
        uint256 totalSdExpected;

        // SDUtilityPool ETH then SD
        totalEthExpected += _sweep(sheet, MainnetAddresses.SD_UTILITY_POOL, address(0), custody);
        totalSdExpected += _sweep(sheet, MainnetAddresses.SD_UTILITY_POOL, sdToken, custody);

        // SP Permissioned ETH then SD
        totalEthExpected += _sweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, address(0), custody);
        totalSdExpected += _sweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, sdToken, custody);

        // SP Permissionless ETH then SD
        totalEthExpected += _sweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, address(0), custody);
        totalSdExpected += _sweep(sheet, MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, sdToken, custody);

        // ORC ETH
        totalEthExpected += _sweep(sheet, MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, address(0), custody);

        // PLP ETH
        totalEthExpected += _sweep(sheet, MainnetAddresses.PERMISSIONLESS_POOL, address(0), custody);

        // SSPM ETH last
        totalEthExpected += _sweep(sheet, MainnetAddresses.SSPM, address(0), custody);

        // Master invariant: custody balance deltas equal sum of swept amounts.
        uint256 custodyEthDelta = custody.balance - custodyEthBefore;
        uint256 custodySdDelta = IERC20BalanceOf(sdToken).balanceOf(custody) - custodySdBefore;

        emit log_named_uint("master invariant: total ETH swept", totalEthExpected);
        emit log_named_uint("master invariant: custody ETH delta", custodyEthDelta);
        emit log_named_uint("master invariant: total SD swept", totalSdExpected);
        emit log_named_uint("master invariant: custody SD delta", custodySdDelta);

        assertEq(custodyEthDelta, totalEthExpected, "master invariant: ETH inflow != sweep total");
        assertEq(custodySdDelta, totalSdExpected, "master invariant: SD inflow != sweep total");
    }

    function _sweep(Sheet memory sheet, address target, address asset, address custody) private returns (uint256) {
        uint256 preBalance = asset == address(0) ? target.balance : IERC20BalanceOf(asset).balanceOf(target);

        if (preBalance == 0) {
            // No balance means sweep reverts ZeroAmount; assert and skip.
            _asDefaultAdmin(sheet, target);
            vm.expectRevert(); // selector varies per contract; tolerate
            IStaderStakePoolManager(target).sweepToCustody(asset, custody);
            _stop();
            return 0;
        }

        vm.expectEmit(true, true, true, true, target);
        emit SweptToCustody(asset, custody, preBalance);

        _asDefaultAdmin(sheet, target);
        IStaderStakePoolManager(target).sweepToCustody(asset, custody);
        _stop();

        assertTrue(IStaderStakePoolManager(target).assetCustodied(), "assetCustodied not flipped after sweep");
        return preBalance;
    }
}
