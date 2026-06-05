// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderConfig } from "contracts/interfaces/IStaderConfig.sol";
import { IStaderOracle } from "contracts/interfaces/IStaderOracle.sol";

interface IAccessControlLite {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IOwnable {
    function owner() external view returns (address);
}

interface INodeRegistryActive {
    function totalActiveValidatorCount() external view returns (uint256);
}

/// @notice Pre-upgrade verification reads. Read-only. Confirms:
///           * sunset state vars are unallocated on every upgraded
///             proxy (vm.load == 0 at known slot indices),
///           * total active validator counts on both NodeRegistry
///             proxies are non-zero,
///           * UWM finalization delay is at its pre-runoff value,
///           * every (role, contract) -> Safe row in the runoff sheet
///             matches on-chain `hasRole` (or `ProxyAdmin.owner()` for
///             `PROXY_ADMIN_OWNER` rows),
///           * oracle exit submission cadence falls within tolerance.
contract PreSunsetVerificationTest is SunsetForkBase {
    /// @notice Sunset slots on every upgraded contract are zero
    ///         pre-upgrade. If any is non-zero, the upgrade would
    ///         collide with existing storage.
    function test_SunsetSlotsUnallocated() public {
        _assertSlotZero(MainnetAddresses.SSPM, MainnetAddresses.SSPM_SLOT_SWEEP_TS, "SSPM.sweepToCustodyTimestamp");
        _assertSlotZero(
            MainnetAddresses.SSPM,
            MainnetAddresses.SSPM_SLOT_PAUSED_AND_CUSTODIED,
            "SSPM.depositsPaused+assetCustodied"
        );
        _assertSlotZero(
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SDUP_SLOT_SWEEP_TS,
            "SDUP.sweepToCustodyTimestamp"
        );
        _assertSlotZero(
            MainnetAddresses.SD_UTILITY_POOL,
            MainnetAddresses.SDUP_SLOT_PAUSED_AND_CUSTODIED,
            "SDUP.depositsPaused+assetCustodied"
        );
        _assertSlotZero(
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SP_SLOT_CUSTODIED,
            "SP_Permissioned.assetCustodied"
        );
        _assertSlotZero(
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED,
            MainnetAddresses.SP_SLOT_SWEEP_TS,
            "SP_Permissioned.sweepToCustodyTimestamp"
        );
        _assertSlotZero(
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.SP_SLOT_CUSTODIED,
            "SP_Permissionless.assetCustodied"
        );
        _assertSlotZero(
            MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS,
            MainnetAddresses.SP_SLOT_SWEEP_TS,
            "SP_Permissionless.sweepToCustodyTimestamp"
        );
        _assertSlotZero(
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.PLP_SLOT_SWEEP_TS,
            "PLP.sweepToCustodyTimestamp"
        );
        _assertSlotZero(
            MainnetAddresses.PERMISSIONLESS_POOL,
            MainnetAddresses.PLP_SLOT_CUSTODIED,
            "PLP.assetCustodied"
        );
        // ORC slot 153 packs assetCustodied at offset 20 with an existing
        // pre-upgrade 20-byte address at offset 0. Check only the bool byte.
        _assertByteZero(
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR,
            MainnetAddresses.ORC_SLOT_CUSTODIED_PACKED,
            20,
            "ORC.assetCustodied (slot 153 byte 20)"
        );
        _assertSlotZero(
            MainnetAddresses.OPERATOR_REWARDS_COLLECTOR,
            MainnetAddresses.ORC_SLOT_SWEEP_TS,
            "ORC.sweepToCustodyTimestamp"
        );
    }

    /// @notice Record total active validators across both registries at
    ///         the freeze block. Ops tracks expected counts off-chain
    ///         (active, offline, exiting, withdraw-queue, exited) per
    ///         pool. The on-chain `totalActiveValidatorCount` is the
    ///         contract's running count of non-exited validators per
    ///         pool. Sanity-asserts both > 0 and emits the counts for
    ///         the runbook to compare against the ops snapshot.
    function test_ActiveValidatorCount() public {
        uint256 pl = INodeRegistryActive(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY).totalActiveValidatorCount();
        uint256 pn = INodeRegistryActive(MainnetAddresses.PERMISSIONED_NODE_REGISTRY).totalActiveValidatorCount();
        emit log_named_uint("Permissionless active (on-chain)", pl);
        emit log_named_uint("Permissioned active (on-chain)", pn);
        emit log_named_uint("Combined active (on-chain)", pl + pn);
        // Sanity: at any pre-sunset block both pools should have
        // non-zero validators. Zero would indicate registry pointer
        // drift or full exit (post-sunset).
        assertGt(pl, 0, "Permissionless registry reports zero active");
        assertGt(pn, 0, "Permissioned registry reports zero active");
    }

    /// @notice Oracle exit-submission cadence stays inside the ~30
    ///         minute window. Reads the gap between the current block
    ///         and `getWithdrawnValidatorReportableBlock()`. Allows a
    ///         generous tolerance (210 blocks ≈ 42 min) since some
    ///         drift between submissions is normal.
    function test_OracleSubmissionCadence() public {
        uint256 reportable = IStaderOracle(MainnetAddresses.STADER_ORACLE).getWithdrawnValidatorReportableBlock();
        uint256 current = block.number;
        uint256 gap = current > reportable ? current - reportable : 0;
        emit log_named_uint("oracle reportable block", reportable);
        emit log_named_uint("current block", current);
        emit log_named_uint("gap (blocks)", gap);
        assertLe(gap, 210, "oracle cadence drift > 42 min");
    }

    /// @notice Pre-OpenInstantRedemption UWM finalization delay is at
    ///         the legacy 7200-block value (~24h). Non-7200 means the
    ///         instant-redemption flip may already have landed.
    function test_UwmFinalizationDelayPreOpenRedemption() public {
        uint256 actual = IStaderConfig(MainnetAddresses.STADER_CONFIG).getMinBlockDelayToFinalizeWithdrawRequest();
        assertEq(actual, 7200, "UWM delay drift; instant-redemption flip may already have run");
    }

    /// @notice For every row in `role_holders.csv`, confirm the named
    ///         Safe holds the named role on the named contract.
    function test_RoleHoldersReconciledOnChain() public {
        Sheet memory sheet = _loadSheet();
        uint256 failed;
        for (uint256 i = 0; i < sheet.roleHolders.length; i++) {
            RoleRow memory r = sheet.roleHolders[i];
            bool ok;
            if (keccak256(bytes(r.roleName)) == keccak256(bytes("PROXY_ADMIN_OWNER"))) {
                ok = IOwnable(r.contractAddress).owner() == r.safeAddress;
            } else {
                bytes32 roleHash = _roleBytes(r.roleName);
                address target = (keccak256(bytes(r.roleName)) == keccak256(bytes("MANAGER")) ||
                    keccak256(bytes(r.roleName)) == keccak256(bytes("OPERATOR")))
                    ? MainnetAddresses.STADER_CONFIG
                    : r.contractAddress;
                try IAccessControlLite(target).hasRole(roleHash, r.safeAddress) returns (bool h) {
                    ok = h;
                } catch {
                    ok = false;
                }
            }
            if (!ok) {
                failed++;
                emit log_named_string("FAIL", string.concat(r.contractName, ".", r.roleName));
                emit log_named_address("  expected safe", r.safeAddress);
            }
        }
        assertEq(failed, 0, "one or more role-holder rows failed reconciliation");
    }

    function _assertSlotZero(address proxy, uint256 slot, string memory label) private {
        bytes32 v = vm.load(proxy, bytes32(slot));
        if (v != bytes32(0)) {
            emit log_named_string("non-zero slot", label);
            emit log_named_uint("  slot", slot);
            emit log_named_bytes32("  value", v);
        }
        assertEq(v, bytes32(0), string.concat("sunset slot not zero: ", label));
    }

    /// @notice Assert a specific byte within a packed slot is zero. Used
    ///         when the sunset field shares its slot with a pre-existing
    ///         variable (e.g. ORC.assetCustodied at slot 153 offset 20,
    ///         where offset 0 holds an existing address).
    function _assertByteZero(address proxy, uint256 slot, uint256 byteOffset, string memory label) private {
        bytes32 v = vm.load(proxy, bytes32(slot));
        uint8 b = uint8(uint256(v) >> (byteOffset * 8));
        if (b != 0) {
            emit log_named_string("non-zero byte in packed slot", label);
            emit log_named_uint("  slot", slot);
            emit log_named_uint("  byteOffset", byteOffset);
            emit log_named_bytes32("  fullValue", v);
        }
        assertEq(uint256(b), uint256(0), string.concat("sunset byte not zero: ", label));
    }

    function _roleBytes(string memory roleName) private pure returns (bytes32) {
        bytes32 h = keccak256(bytes(roleName));
        if (h == keccak256(bytes("DEFAULT_ADMIN_ROLE"))) return bytes32(0);
        if (h == keccak256(bytes("MANAGER"))) return keccak256("MANAGER");
        if (h == keccak256(bytes("OPERATOR"))) return keccak256("OPERATOR");
        return keccak256(bytes(roleName)); // generic fallback
    }
}
