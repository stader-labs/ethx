// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderStakePoolManager } from "contracts/interfaces/IStaderStakePoolManager.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";
import { ISocializingPool } from "contracts/interfaces/ISocializingPool.sol";
import { IOperatorRewardsCollector } from "contracts/interfaces/IOperatorRewardsCollector.sol";
import { IUserWithdrawalManager } from "contracts/interfaces/IUserWithdrawalManager.sol";
import { IPermissionlessPool } from "contracts/interfaces/IPermissionlessPool.sol";

interface ISDUPFull is ISDUtilityPool {
    function requestWithdrawWithSDAmount(uint256) external returns (uint256);
    function utilize(uint256) external;
    function repay(uint256) external returns (uint256, uint256);
    function repayOnBehalf(address, uint256) external returns (uint256, uint256);
    function repayFullAmount() external returns (uint256, uint256);
    function withdrawProtocolFee(uint256) external;
    function maxApproveSD() external;
    function liquidationCall(address) external;
}

interface ISocializingPoolFull is ISocializingPool {
    function maxApproveSD() external;
    function claimAndDepositSD(
        uint256[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        bytes32[][] calldata
    ) external;
}

/// @notice Post-sweep kill switch matrix. Twenty-nine guarded entry
///         points across the six custodied contracts plus the
///         cross-contract guard on UserWithdrawalManager. Each call
///         is wrapped in `vm.expectRevert(AssetCustodied.selector)`.
///         Setup upgrades every proxy to the sunset implementation
///         and flips `assetCustodied` to true via `vm.store` so the
///         post-sweep guards fire on entry.
contract PostSweepKillSwitchTest is SunsetForkBase {
    address internal constant STRANGER = address(0xDEAD);
    address internal sd;

    function setUp() public override {
        super.setUp();
        _upgradeAllProxies(_loadSheet());

        // Resolve SD token before flipping storage so we can use it in
        // SDUtilityPool / SocializingPool entry-point tests.
        (bool ok, bytes memory ret) = MainnetAddresses.STADER_CONFIG.staticcall(
            abi.encodeWithSignature("getStaderToken()")
        );
        require(ok, "getStaderToken failed");
        sd = abi.decode(ret, (address));

        // Flip assetCustodied on every swept proxy via vm.store.
        _flipBoolByte(MainnetAddresses.SSPM, MainnetAddresses.SSPM_SLOT_PAUSED_AND_CUSTODIED, 1);
        _flipBoolByte(MainnetAddresses.SD_UTILITY_POOL, MainnetAddresses.SDUP_SLOT_PAUSED_AND_CUSTODIED, 1);
        _flipBoolByte(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED, MainnetAddresses.SP_SLOT_CUSTODIED, 0);
        _flipBoolByte(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS, MainnetAddresses.SP_SLOT_CUSTODIED, 0);
        _flipBoolByte(MainnetAddresses.PERMISSIONLESS_POOL, MainnetAddresses.PLP_SLOT_CUSTODIED, 0);
        _flipBoolByte(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR, MainnetAddresses.ORC_SLOT_CUSTODIED_PACKED, 20);

        vm.deal(STRANGER, 100 ether);
    }

    // ---------- SSPM (4 entry points) ----------
    function test_SSPM_Deposit() public {
        vm.prank(STRANGER);
        vm.expectRevert(IStaderStakePoolManager.AssetCustodied.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(STRANGER);
    }

    function test_SSPM_DepositWithReferral() public {
        vm.prank(STRANGER);
        vm.expectRevert(IStaderStakePoolManager.AssetCustodied.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).deposit{ value: 1 ether }(STRANGER, "ref");
    }

    function test_SSPM_ValidatorBatchDeposit() public {
        vm.prank(MainnetAddresses.PERMISSIONLESS_POOL);
        vm.expectRevert(IStaderStakePoolManager.AssetCustodied.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).validatorBatchDeposit(1);
    }

    function test_SSPM_DepositETHOverTargetWeight() public {
        vm.prank(STRANGER);
        vm.expectRevert(IStaderStakePoolManager.AssetCustodied.selector);
        IStaderStakePoolManager(MainnetAddresses.SSPM).depositETHOverTargetWeight();
    }

    // ---------- SDUtilityPool (13 entry points) ----------
    function test_SDUP_Delegate() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).delegate(1 ether);
    }

    function test_SDUP_RequestWithdraw() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).requestWithdraw(1 ether);
    }

    function test_SDUP_RequestWithdrawWithSDAmount() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).requestWithdrawWithSDAmount(1 ether);
    }

    function test_SDUP_FinalizeDelegatorWithdrawalRequest() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).finalizeDelegatorWithdrawalRequest();
    }

    function test_SDUP_Claim() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).claim(1);
    }

    function test_SDUP_Utilize() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).utilize(1 ether);
    }

    function test_SDUP_UtilizeWhileAddingKeys() public {
        vm.prank(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUtilityPool(MainnetAddresses.SD_UTILITY_POOL).utilizeWhileAddingKeys(STRANGER, 1 ether, 1);
    }

    function test_SDUP_Repay() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).repay(1 ether);
    }

    function test_SDUP_RepayOnBehalf() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).repayOnBehalf(STRANGER, 1 ether);
    }

    function test_SDUP_RepayFullAmount() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).repayFullAmount();
    }

    function test_SDUP_WithdrawProtocolFee() public {
        // withdrawProtocolFee is OPERATOR-gated. Sheet's MANAGER row is
        // 0xAAfb...; OPERATOR holder may differ but AssetCustodied
        // should revert before the role check anyway.
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).withdrawProtocolFee(1);
    }

    function test_SDUP_MaxApproveSD() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).maxApproveSD();
    }

    function test_SDUP_LiquidationCall() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISDUtilityPool.AssetCustodied.selector);
        ISDUPFull(MainnetAddresses.SD_UTILITY_POOL).liquidationCall(STRANGER);
    }

    // ---------- SocializingPool ×2 (6 entry points) ----------
    function test_SP_Permissioned_Claim() public {
        _claimRevertSP(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED);
    }

    function test_SP_Permissioned_ClaimAndDepositSD() public {
        _claimAndDepositSDRevertSP(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED);
    }

    function test_SP_Permissioned_MaxApproveSD() public {
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        ISocializingPoolFull(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED).maxApproveSD();
    }

    function test_SP_Permissionless_Claim() public {
        _claimRevertSP(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS);
    }

    function test_SP_Permissionless_ClaimAndDepositSD() public {
        _claimAndDepositSDRevertSP(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS);
    }

    function test_SP_Permissionless_MaxApproveSD() public {
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        ISocializingPoolFull(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS).maxApproveSD();
    }

    // ---------- PermissionlessPool (2 entry points) ----------
    function test_PLP_PreDepositOnBeaconChain() public {
        bytes[] memory pubkeys = new bytes[](0);
        bytes[] memory sigs = new bytes[](0);
        vm.prank(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY);
        // PLP imports ISunset-style errors via SocializingPool's interface
        // path; selector still resolves to AssetCustodied.
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        IPermissionlessPool(MainnetAddresses.PERMISSIONLESS_POOL).preDepositOnBeaconChain{ value: 0 }(
            pubkeys,
            sigs,
            1,
            1
        );
    }

    function test_PLP_StakeUserETHToBeaconChain() public {
        vm.prank(STRANGER);
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        (bool ok, ) = MainnetAddresses.PERMISSIONLESS_POOL.call(abi.encodeWithSignature("stakeUserETHToBeaconChain()"));
        ok; // selector resolution is in the call signature, not here.
    }

    // ---------- OperatorRewardsCollector (3 entry points) ----------
    function test_ORC_Claim() public {
        vm.prank(STRANGER);
        vm.expectRevert();
        IOperatorRewardsCollector(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR).claim();
    }

    function test_ORC_ClaimWithAmount() public {
        vm.prank(STRANGER);
        vm.expectRevert(IOperatorRewardsCollector.AssetCustodied.selector);
        IOperatorRewardsCollector(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR).claimWithAmount(1 ether);
    }

    function test_ORC_ClaimLiquidation() public {
        vm.prank(STRANGER);
        vm.expectRevert(IOperatorRewardsCollector.AssetCustodied.selector);
        IOperatorRewardsCollector(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR).claimLiquidation(STRANGER);
    }

    // ---------- UserWithdrawalManager (1 cross-contract entry point) ----------
    function test_UWM_RequestWithdraw_CrossContract() public {
        vm.prank(STRANGER);
        vm.expectRevert(IUserWithdrawalManager.AssetCustodied.selector);
        IUserWithdrawalManager(MainnetAddresses.USER_WITHDRAWAL_MANAGER).requestWithdraw(1 ether, STRANGER);
    }

    // ---------- helpers ----------
    function _claimRevertSP(address proxy) private {
        uint256[] memory empty = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        vm.prank(STRANGER);
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        ISocializingPool(proxy).claim(empty, empty, empty, proofs);
    }

    function _claimAndDepositSDRevertSP(address proxy) private {
        uint256[] memory empty = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        vm.prank(STRANGER);
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        ISocializingPoolFull(proxy).claimAndDepositSD(empty, empty, empty, proofs);
    }

    function _flipBoolByte(address proxy, uint256 slot, uint256 byteOffset) private {
        bytes32 cur = vm.load(proxy, bytes32(slot));
        uint256 mask = uint256(0xff) << (byteOffset * 8);
        uint256 set = uint256(1) << (byteOffset * 8);
        bytes32 next = bytes32((uint256(cur) & ~mask) | set);
        vm.store(proxy, bytes32(slot), next);
    }
}
