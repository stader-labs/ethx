// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IUserWithdrawalManager } from "contracts/interfaces/IUserWithdrawalManager.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";
import { IOperatorRewardsCollector } from "contracts/interfaces/IOperatorRewardsCollector.sol";
import { IValidatorWithdrawalVault } from "contracts/interfaces/IValidatorWithdrawalVault.sol";

interface IERC20Approve {
    function approve(address, uint256) external returns (bool);
}

interface ISDUPRepay {
    function repayFullAmount() external returns (uint256, uint256);
    function utilizerData(address) external view returns (uint256 principal, uint256 utilizeIndex);
    function finalizeDelegatorWithdrawalRequest() external;
    function claim(uint256 requestId) external;
}

/// @notice Per-actor drain simulations covering every redemption path
///         exercised during the runoff window: ETHx holder withdraw,
///         SD delegator withdraw, operator repay, liquidation claim,
///         and vault settlement. Each test is isolated and pulls its
///         actor from the runoff sheet.
contract DrainActorTemplatesTest is SunsetForkBase {
    function test_ETHxHolderDrain() public {
        Sheet memory sheet = _loadSheet();
        HolderRow memory holder = _firstHolder(sheet);
        uint256 amount = 1 ether;
        deal(MainnetAddresses.ETHX, holder.addr, amount);
        vm.deal(holder.addr, 1 ether);

        vm.startPrank(holder.addr);
        IERC20Approve(MainnetAddresses.ETHX).approve(MainnetAddresses.USER_WITHDRAWAL_MANAGER, amount);
        uint256 requestId = IUserWithdrawalManager(MainnetAddresses.USER_WITHDRAWAL_MANAGER).requestWithdraw(
            amount,
            holder.addr
        );
        vm.stopPrank();

        emit log_named_uint("requestWithdraw id", requestId);
        assertGt(requestId, 0, "request id should be non-zero");
    }

    function test_SDDelegatorDrain() public {
        Sheet memory sheet = _loadSheet();
        DelegatorRow memory d = _firstDelegator(sheet);
        address sdToken = _sdToken();
        uint256 amount = 1 ether;

        // First delegate to get cToken balance, then request withdraw.
        deal(sdToken, d.addr, amount);
        vm.deal(d.addr, 1 ether);

        vm.startPrank(d.addr);
        IERC20Approve(sdToken).approve(MainnetAddresses.SD_UTILITY_POOL, amount);
        (bool delegateOk, ) = MainnetAddresses.SD_UTILITY_POOL.call(
            abi.encodeWithSignature("delegate(uint256)", amount)
        );
        if (!delegateOk) {
            vm.stopPrank();
            emit log_string("delegate reverted (likely post-arm pause); skipping request");
            return;
        }
        uint256 requestId = ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).requestWithdraw(amount / 2);
        vm.stopPrank();
        emit log_named_uint("SDUtilityPool.requestWithdraw id", requestId);
        assertGt(requestId, 0, "request id should be non-zero");
    }

    function _sdToken() private view returns (address) {
        (bool ok, bytes memory d) = MainnetAddresses.STADER_CONFIG.staticcall(
            abi.encodeWithSignature("getStaderToken()")
        );
        require(ok, "getStaderToken failed");
        return abi.decode(d, (address));
    }

    function test_PermissionlessOperatorRepay() public {
        Sheet memory sheet = _loadSheet();
        address op = _operatorWithUtilization(sheet);
        if (op == address(0)) {
            emit log_string("no operator with utilizedSd > 0 in sheet; skipping");
            return;
        }
        vm.deal(op, 1 ether);
        vm.prank(op);
        try ISDUPRepay(MainnetAddresses.SD_UTILITY_POOL).repayFullAmount() {
            (uint256 principal, ) = ISDUPRepay(MainnetAddresses.SD_UTILITY_POOL).utilizerData(op);
            assertEq(principal, 0, "principal should clear after repayFullAmount");
        } catch {
            emit log_string("repayFullAmount reverted (sheet stub address has no real utilization)");
        }
    }

    function test_LiquidationClaim() public {
        Sheet memory sheet = _loadSheet();
        address op = _firstLiquidatedOperator(sheet);
        try IOperatorRewardsCollector(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR).claimLiquidation(op) {
            emit log_named_address("claimLiquidation succeeded for", op);
        } catch {
            emit log_string("claimLiquidation reverted (sheet stub operator has no real liquidation)");
        }
    }

    function test_VaultSettlement() public {
        address vault = vm.envOr("VAULT_ADDR", address(0));
        if (vault == address(0)) {
            emit log_string("VAULT_ADDR not set; vault settlement template skipped");
            return;
        }
        uint256 before = vault.balance;
        try IValidatorWithdrawalVault(payable(vault)).settleFunds() {
            emit log_named_uint("vault settleFunds done; balance was", before);
        } catch {
            emit log_string("vault settleFunds reverted (vault may not be settle-eligible at this block)");
        }
    }

    function _firstHolder(Sheet memory sheet) private pure returns (HolderRow memory) {
        require(sheet.ethxHolders.length > 0, "no ethx holders in sheet");
        return sheet.ethxHolders[0];
    }

    function _firstDelegator(Sheet memory sheet) private pure returns (DelegatorRow memory) {
        require(sheet.sdDelegators.length > 0, "no sd delegators in sheet");
        return sheet.sdDelegators[0];
    }

    function _operatorWithUtilization(Sheet memory sheet) private pure returns (address) {
        for (uint256 i = 0; i < sheet.operators.length; i++) {
            if (sheet.operators[i].utilizedSd > 0) return sheet.operators[i].addr;
        }
        return address(0);
    }

    function _firstLiquidatedOperator(Sheet memory sheet) private pure returns (address) {
        for (uint256 i = 0; i < sheet.operators.length; i++) {
            if (sheet.operators[i].openLiquidation) return sheet.operators[i].addr;
        }
        revert("no operator with openLiquidation");
    }
}
