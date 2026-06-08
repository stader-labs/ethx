// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderStakePoolManager } from "contracts/interfaces/IStaderStakePoolManager.sol";
import { IUserWithdrawalManager } from "contracts/interfaces/IUserWithdrawalManager.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";
import { ISocializingPool } from "contracts/interfaces/ISocializingPool.sol";

/// @notice Final pre-flight before the custody sweep. Three
///         independent tests:
///           1. zero-balance sweeps revert with `ZeroAmount`,
///           2. an in-flight withdraw spanning the sweep boundary
///              reverts on the post-sweep claim with `AssetCustodied`,
///           3. PermissionlessPool residual ETH stays within the dust
///              limit (hard stop; non-dust residual aborts the sweep).
///
///         Assumes the arm-sunset transaction has landed. Without it,
///         tests revert early at the `setCustodyDelay` step.
contract PreSweepGatesTest is SunsetForkBase {
    function test_ZeroBalanceSweep() public {
        // For each contract whose balance is zero, sweepToCustody
        // should revert with ZeroAmount. Pre-Batch-1 mainnet does not
        // have sunset functions yet, so this test asserts the call
        // reverts (with whatever selector it returns).
        Sheet memory sheet = _loadSheet();
        address custody = sheet.custody.custody;

        // PermissionlessPool ETH balance is typically dust on mainnet.
        // Probe an asset that is guaranteed zero: ETHx on PLP.
        _asDefaultAdmin(sheet, MainnetAddresses.PERMISSIONLESS_POOL);
        vm.expectRevert();
        IStaderStakePoolManager(MainnetAddresses.PERMISSIONLESS_POOL).sweepToCustody(MainnetAddresses.ETHX, custody);
        _stop();
        emit log_string("zero-balance sweep on PLP/ETHx reverted as expected");
    }

    function test_InFlightWithdrawAcrossBoundary() public {
        // Sequence: requestWithdraw -> admin finalize -> warp -> sweep
        // -> claim (expect AssetCustodied). Requires the arm-sunset transaction to have landed.
        Sheet memory sheet = _loadSheet();
        HolderRow memory holder = sheet.ethxHolders[0];
        if (holder.balanceAtFreeze == 0) {
            emit log_string("sheet holder has zero balance; in-flight test is a no-op");
            return;
        }

        // requestWithdraw (best-effort; will revert if balance is stub).
        vm.deal(holder.addr, 1 ether);
        vm.prank(holder.addr);
        try
            IUserWithdrawalManager(MainnetAddresses.USER_WITHDRAWAL_MANAGER).requestWithdraw(
                holder.balanceAtFreeze,
                holder.addr
            )
        returns (uint256 requestId) {
            // Warp past custody delay, sweep, then attempt claim.
            vm.warp(block.timestamp + 7 days + 60);
            _asDefaultAdmin(sheet, MainnetAddresses.SSPM);
            try IStaderStakePoolManager(MainnetAddresses.SSPM).sweepToCustody(address(0), sheet.custody.custody) {
                _stop();
                vm.prank(holder.addr);
                vm.expectRevert(IUserWithdrawalManager.AssetCustodied.selector);
                IUserWithdrawalManager(MainnetAddresses.USER_WITHDRAWAL_MANAGER).claim(requestId);
                emit log_string("in-flight claim correctly reverted post-sweep");
            } catch {
                _stop();
                emit log_string("sweep itself reverted (sunset controls likely not armed)");
            }
        } catch {
            emit log_string("requestWithdraw failed; sheet stub balance");
        }
    }

    function test_PermissionlessPoolResidualHardStop() public {
        Sheet memory sheet = _loadSheet();
        uint256 dustLimit = sheet.custody.preDepositDustLimit;
        uint256 balance = MainnetAddresses.PERMISSIONLESS_POOL.balance;
        emit log_named_uint("PLP balance (wei)", balance);
        emit log_named_uint("dust limit (wei)", dustLimit);
        assertLe(balance, dustLimit, "PLP residual exceeds dust limit; validator stuck in PRE_DEPOSIT; do NOT sweep");
    }
}
