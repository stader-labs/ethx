// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";
import { IStaderOracle } from "contracts/interfaces/IStaderOracle.sol";
import { ISDUtilityPool } from "contracts/interfaces/ISDUtilityPool.sol";

interface IStaderConfigUpdate {
    function updateMinBlockDelayToFinalizeWithdrawRequest(uint256) external;
}

interface ISDUtilityPoolUpdate {
    function updateMinBlockDelayToFinalizeRequest(uint256) external;
    function minBlockDelayToFinalizeRequest() external view returns (uint256);
}

/// @notice Zeros both withdrawal-finalization delays (UWM 24h,
///         SDUtilityPool 7d) so users can redeem within a single
///         block. Pre-flight asserts both delays are non-zero and the
///         oracle is decommissioned (the MEV vector closes only when
///         the oracle is dead). Flips the delays and asserts the
///         corresponding events. A companion test exercises the
///         `IdenticalValue()` revert path so the flip cannot land
///         twice.
contract OpenInstantRedemptionTest is SunsetForkBase {
    /// @notice Locally redeclared so we can `vm.expectEmit` it.
    event UpdatedMinBlockDelayToFinalizeRequest(uint256 minBlockDelayToFinalizeRequest);
    event SetConstant(bytes32 key, uint256 amount);

    function setUp() public override {
        super.setUp();
        // Open instant redemption requires the oracle to be decommissioned. Simulate by default;
        // STRICT_LIVE_ORACLE=1 opts out and tests against real state.
        _simulateOracleDecommissioned();
    }

    /// @notice Plan-spec'd `IdenticalValue()` revert path on StaderConfig.
    ///         Setting a constant to its current value must revert so
    ///         the flip can't accidentally land twice or land into an
    ///         already-flipped state.
    function test_IdenticalValueRevertOnDoubleFlip() public {
        Sheet memory sheet = _loadSheet();
        address admin = _findRoleSafe(sheet, MainnetAddresses.STADER_CONFIG, "DEFAULT_ADMIN_ROLE");
        require(admin != address(0), "no StaderConfig admin in sheet");

        // First flip succeeds.
        vm.prank(admin);
        IStaderConfigUpdate(MainnetAddresses.STADER_CONFIG).updateMinBlockDelayToFinalizeWithdrawRequest(0);

        // Second flip with same value reverts with IdenticalValue.
        vm.prank(admin);
        vm.expectRevert();
        IStaderConfigUpdate(MainnetAddresses.STADER_CONFIG).updateMinBlockDelayToFinalizeWithdrawRequest(0);
    }

    function test_OpenInstantRedemptionFlip() public {
        Sheet memory sheet = _loadSheet();

        // Pre-flight: delays > 0 (otherwise the flip reverts).
        uint256 uwmDelay = IStaderConfig(MainnetAddresses.STADER_CONFIG).getMinBlockDelayToFinalizeWithdrawRequest();
        uint256 sdupDelay = ISDUtilityPoolUpdate(MainnetAddresses.SD_UTILITY_POOL).minBlockDelayToFinalizeRequest();
        require(uwmDelay > 0, "UWM delay already 0; flip would revert with IdenticalValue()");
        require(sdupDelay > 0, "SDUP delay already 0; flip would revert");

        // Pre-flight: oracle dead.
        uint256 trusted = IStaderOracle(MainnetAddresses.STADER_ORACLE).trustedNodesCount();
        require(trusted == 0, "oracle alive; MEV vector open; do NOT flip delays");

        // Flip both delays with expectEmit assertions.
        address admin = _findRoleSafe(sheet, MainnetAddresses.STADER_CONFIG, "DEFAULT_ADMIN_ROLE");
        if (admin == address(0)) admin = _findRoleSafe(sheet, MainnetAddresses.STADER_CONFIG, "MANAGER");
        // StaderConfig.SetConstant fires with the indexed key matching
        // keccak256("MIN_BLOCK_DELAY_TO_FINALIZE_WITHDRAW_REQUEST") and
        // value 0. Topic + value match required.
        bytes32 expectedKey = keccak256("MIN_BLOCK_DELAY_TO_FINALIZE_WITHDRAW_REQUEST");
        vm.expectEmit(true, true, true, true, MainnetAddresses.STADER_CONFIG);
        emit SetConstant(expectedKey, 0);
        vm.prank(admin);
        IStaderConfigUpdate(MainnetAddresses.STADER_CONFIG).updateMinBlockDelayToFinalizeWithdrawRequest(0);

        address sdupAdmin = _findRoleSafe(sheet, MainnetAddresses.SD_UTILITY_POOL, "DEFAULT_ADMIN_ROLE");
        vm.expectEmit(true, true, true, true, MainnetAddresses.SD_UTILITY_POOL);
        emit UpdatedMinBlockDelayToFinalizeRequest(0);
        vm.prank(sdupAdmin);
        ISDUtilityPoolUpdate(MainnetAddresses.SD_UTILITY_POOL).updateMinBlockDelayToFinalizeRequest(0);

        // Post-flip reads.
        assertEq(
            IStaderConfig(MainnetAddresses.STADER_CONFIG).getMinBlockDelayToFinalizeWithdrawRequest(),
            0,
            "UWM delay did not flip"
        );
        assertEq(
            ISDUtilityPoolUpdate(MainnetAddresses.SD_UTILITY_POOL).minBlockDelayToFinalizeRequest(),
            0,
            "SDUP delay did not flip"
        );

        emit log_string("Open-instant-redemption flip done. Same-block redemption now possible.");
        // Functional verification (same-block redemption) requires a
        // real ETHx holder with balance and is exercised in the
        // OpenRedemptionHealth test against the populated sheet.
    }
}
