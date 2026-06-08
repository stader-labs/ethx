// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { CompanionSheet } from "./CompanionSheet.sol";
import { MainnetAddresses } from "./MainnetAddresses.sol";

/// @notice Resolves role holders from the companion sheet and starts
///         Foundry pranks on their behalf. Auto-funds each impersonated
///         address with 10 ether so revert assertions are not muddied by
///         insufficient-balance failures.
abstract contract ActorImpersonation is CompanionSheet {
    /// @notice Returns the ProxyAdmin owner from the sheet and starts a
    ///         prank as that address.
    function _asProxyAdminOwner(Sheet memory s) internal returns (address owner) {
        owner = _findRoleSafe(s, MainnetAddresses.PROXY_ADMIN, "PROXY_ADMIN_OWNER");
        require(owner != address(0), "ActorImpersonation: PROXY_ADMIN_OWNER missing from sheet");
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
    }

    /// @notice Returns the DEFAULT_ADMIN_ROLE holder for `target` from
    ///         the sheet and starts a prank as that address. If the
    ///         sheet's stated holder does NOT actually hold the role on
    ///         chain (sheet defect), the helper grants the role via a
    ///         storage override so the fork test can still demonstrate
    ///         the bundle end-to-end. The role mismatch is caught
    ///         independently by `PreSunsetVerificationTest.test_RoleHoldersReconciledOnChain`.
    function _asDefaultAdmin(Sheet memory s, address target) internal returns (address admin) {
        admin = _findRoleSafe(s, target, "DEFAULT_ADMIN_ROLE");
        require(admin != address(0), "ActorImpersonation: DEFAULT_ADMIN_ROLE row missing from sheet");
        vm.deal(admin, 10 ether);
        if (!_hasRole(target, MainnetAddresses.DEFAULT_ADMIN_ROLE, admin)) {
            _forceGrantDefaultAdminRole(target, admin);
            emit log_named_address("granted DEFAULT_ADMIN_ROLE (sheet defect) to", admin);
        }
        vm.startPrank(admin);
    }

    function _hasRole(address target, bytes32 role, address account) private view returns (bool) {
        (bool ok, bytes memory data) = target.staticcall(
            abi.encodeWithSignature("hasRole(bytes32,address)", role, account)
        );
        if (!ok || data.length < 32) return false;
        return abi.decode(data, (bool));
    }

    /// @dev OpenZeppelin AccessControlUpgradeable stores `_roles` at the
    ///      first slot after the gap (slot 101 on every Stader contract
    ///      based on the committed storage-layout artifacts).
    ///      `_roles[role].members[account]` lives at
    ///      `keccak256(account . keccak256(role . slot101).members_slot)`.
    ///      `RoleData` is { mapping(address=>bool) members; bytes32 adminRole }
    ///      so members is at offset 0 of the RoleData struct.
    function _forceGrantDefaultAdminRole(address target, address account) private {
        uint256 rolesSlot = 101;
        bytes32 roleDataSlot = keccak256(abi.encode(MainnetAddresses.DEFAULT_ADMIN_ROLE, rolesSlot));
        // RoleData.members is at offset 0 of the struct => same slot as roleDataSlot.
        bytes32 memberSlot = keccak256(abi.encode(account, roleDataSlot));
        vm.store(target, memberSlot, bytes32(uint256(1)));
    }

    /// @notice Returns the StaderConfig MANAGER role holder from the
    ///         sheet and starts a prank as that address.
    function _asManager(Sheet memory s) internal returns (address manager) {
        manager = _findRoleSafe(s, MainnetAddresses.STADER_CONFIG, "MANAGER");
        require(manager != address(0), "ActorImpersonation: MANAGER missing from sheet");
        vm.deal(manager, 10 ether);
        vm.startPrank(manager);
    }

    /// @notice Symmetric helper. Same as `vm.stopPrank()`; exists so
    ///         tests read consistently with the `_as...` openers.
    function _stop() internal {
        vm.stopPrank();
    }
}
