// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Mainnet proxy + config + role addresses for the ethX sunset
///         fork tests. Source: scripts/safe-scripts/address.json
///         (mainnet section) and contracts/StaderConfig.sol role constants.
library MainnetAddresses {
    // ProxyAdmin (TransparentUpgradeableProxy admin for every proxy below).
    address internal constant PROXY_ADMIN = 0x67B12264Ca3e0037Fc7E22F2457b42643a04C86e;

    // Sunset target proxies (upgraded by ArmSunsetControls).
    address internal constant SSPM = 0xcf5EA1b38380f6aF39068375516Daf40Ed70D299;
    address internal constant SD_UTILITY_POOL = 0xED6EE5049f643289ad52411E9aDeC698D04a9602;
    address internal constant SOCIALIZING_POOL_PERMISSIONED = 0x9d4C3166c59412CEdBe7d901f5fDe41903a1d6Fc;
    address internal constant SOCIALIZING_POOL_PERMISSIONLESS = 0x1DE458031bFbe5689deD5A8b9ed57e1E79EaB2A4;
    address internal constant PERMISSIONLESS_POOL = 0xd1a72Bd052e0d65B7c26D3dd97A98B74AcbBb6c5;
    address internal constant OPERATOR_REWARDS_COLLECTOR = 0x84ffDC9De310144D889540A49052F6d1AdB2C335;
    address internal constant USER_WITHDRAWAL_MANAGER = 0x9F0491B32DBce587c50c4C43AB303b06478193A7;

    // Config and adjacent contracts (read targets, not upgrade targets).
    address internal constant STADER_CONFIG = 0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB;
    address internal constant STADER_ORACLE = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    address internal constant SD_COLLATERAL = 0x7Af4730cc8EbAd1a050dcad5c03c33D2793EE91f;
    address internal constant PERMISSIONLESS_NODE_REGISTRY = 0x4f4Bfa0861F62309934a5551E0B2541Ee82fdcF1;
    address internal constant PERMISSIONED_NODE_REGISTRY = 0xaf42d795A6D279e9DCc19DC0eE1cE3ecd4ecf5dD;
    address internal constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;

    // Default custody delay used by ArmSunsetControls setCustodyDelay calls.
    uint256 internal constant DEFAULT_CUSTODY_DELAY = 7 days;

    // Role bytes32 constants. DEFAULT_ADMIN_ROLE = bytes32(0) from
    // OpenZeppelin AccessControl. MANAGER and OPERATOR are keccak256
    // hashes used by StaderConfig.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR");

    // Storage slot indices for sunset state variables on each upgraded
    // contract. Source: `forge inspect <C> storage-layout` artifacts
    // committed under test/fork/sunset/layouts/. Phase 0 verification
    // reads `vm.load(proxy, slot)` to confirm slots are zero before
    // the arm-sunset transaction lands (i.e. the sunset fields do not collide with
    // pre-existing storage).
    uint256 internal constant SSPM_SLOT_SWEEP_TS = 254;
    uint256 internal constant SSPM_SLOT_PAUSED_AND_CUSTODIED = 255;
    uint256 internal constant SDUP_SLOT_SWEEP_TS = 229;
    uint256 internal constant SDUP_SLOT_PAUSED_AND_CUSTODIED = 230;
    uint256 internal constant SP_SLOT_CUSTODIED = 266;
    uint256 internal constant SP_SLOT_SWEEP_TS = 267;
    uint256 internal constant PLP_SLOT_SWEEP_TS = 204;
    uint256 internal constant PLP_SLOT_CUSTODIED = 205;
    uint256 internal constant ORC_SLOT_CUSTODIED_PACKED = 153;
    uint256 internal constant ORC_SLOT_SWEEP_TS = 154;
}
