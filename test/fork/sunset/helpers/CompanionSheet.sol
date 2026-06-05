// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

/// @notice Loader for the ethX sunset runoff sheet JSON. Single source
///         of truth for actor lists, role mappings, custody config,
///         and the ghost-batch slice. Default path is
///         `./test/fork/sunset/fixtures/runoff-sheet.json`; override
///         via the `COMPANION_SHEET_PATH` env var.
///
/// @dev    Numeric fields in the JSON are stored as strings to keep
///         large wei values precision-safe. `vm.parseJsonUint` reads
///         either string or numeric JSON values into uint256.
abstract contract CompanionSheet is Test {
    struct OperatorRow {
        address addr;
        address reward;
        string pool;
        uint256 totalKeys;
        uint256 nonTerminalKeys;
        uint256 sdCollateral;
        uint256 utilizedSd;
        uint256 interestSd;
        uint256 ethInOrc;
        bool openLiquidation;
        string status;
        string contact;
    }

    struct HolderRow {
        address addr;
        uint256 balanceAtFreeze;
    }

    struct DelegatorRow {
        address addr;
        uint256 ctokenBalance;
        uint256 sdBalance;
    }

    struct RoleRow {
        string contractName;
        address contractAddress;
        string roleName;
        address safeAddress;
    }

    struct CustodyConfig {
        address custody;
        address treasury;
        uint256 preDepositDustLimit;
        address[] oracleQuorum;
    }

    struct GhostBatchRow {
        address addr;
        uint256 interestSd;
        string note;
    }

    struct Sheet {
        OperatorRow[] operators;
        HolderRow[] ethxHolders;
        DelegatorRow[] sdDelegators;
        RoleRow[] roleHolders;
        CustodyConfig custody;
        GhostBatchRow[] ghostBatch;
    }

    string internal constant DEFAULT_SHEET_PATH = "./test/fork/sunset/fixtures/runoff-sheet.json";

    function _sheetPath() internal returns (string memory) {
        return vm.envOr("COMPANION_SHEET_PATH", string(DEFAULT_SHEET_PATH));
    }

    function _loadSheet() internal returns (Sheet memory s) {
        string memory raw = vm.readFile(_sheetPath());
        s.operators = _loadOperators(raw);
        s.ethxHolders = _loadHolders(raw);
        s.sdDelegators = _loadDelegators(raw);
        s.roleHolders = _loadRoleHolders(raw);
        s.custody = _loadCustody(raw);
        s.ghostBatch = _loadGhostBatch(raw);
    }

    function _count(string memory raw, string memory slice) private returns (uint256) {
        return vm.parseJsonUint(raw, string.concat("$.counts.", slice));
    }

    function _loadOperators(string memory raw) private returns (OperatorRow[] memory rows) {
        uint256 n = _count(raw, "operators");
        rows = new OperatorRow[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat("$.operators[", vm.toString(i), "].");
            rows[i] = OperatorRow({
                addr: vm.parseJsonAddress(raw, string.concat(base, "address")),
                reward: vm.parseJsonAddress(raw, string.concat(base, "reward")),
                pool: vm.parseJsonString(raw, string.concat(base, "pool")),
                totalKeys: vm.parseJsonUint(raw, string.concat(base, "totalKeys")),
                nonTerminalKeys: vm.parseJsonUint(raw, string.concat(base, "nonTerminalKeys")),
                sdCollateral: vm.parseJsonUint(raw, string.concat(base, "sdCollateral")),
                utilizedSd: vm.parseJsonUint(raw, string.concat(base, "utilizedSd")),
                interestSd: vm.parseJsonUint(raw, string.concat(base, "interestSd")),
                ethInOrc: vm.parseJsonUint(raw, string.concat(base, "ethInOrc")),
                openLiquidation: vm.parseJsonBool(raw, string.concat(base, "openLiquidation")),
                status: vm.parseJsonString(raw, string.concat(base, "status")),
                contact: vm.parseJsonString(raw, string.concat(base, "contact"))
            });
        }
    }

    function _loadHolders(string memory raw) private returns (HolderRow[] memory rows) {
        uint256 n = _count(raw, "ethxHolders");
        rows = new HolderRow[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat("$.ethxHolders[", vm.toString(i), "].");
            rows[i] = HolderRow({
                addr: vm.parseJsonAddress(raw, string.concat(base, "address")),
                balanceAtFreeze: vm.parseJsonUint(raw, string.concat(base, "balanceAtFreeze"))
            });
        }
    }

    function _loadDelegators(string memory raw) private returns (DelegatorRow[] memory rows) {
        uint256 n = _count(raw, "sdDelegators");
        rows = new DelegatorRow[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat("$.sdDelegators[", vm.toString(i), "].");
            rows[i] = DelegatorRow({
                addr: vm.parseJsonAddress(raw, string.concat(base, "address")),
                ctokenBalance: vm.parseJsonUint(raw, string.concat(base, "ctokenBalance")),
                sdBalance: vm.parseJsonUint(raw, string.concat(base, "sdBalance"))
            });
        }
    }

    function _loadRoleHolders(string memory raw) private returns (RoleRow[] memory rows) {
        uint256 n = _count(raw, "roleHolders");
        rows = new RoleRow[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat("$.roleHolders[", vm.toString(i), "].");
            rows[i] = RoleRow({
                contractName: vm.parseJsonString(raw, string.concat(base, "contractName")),
                contractAddress: vm.parseJsonAddress(raw, string.concat(base, "contractAddress")),
                roleName: vm.parseJsonString(raw, string.concat(base, "roleName")),
                safeAddress: vm.parseJsonAddress(raw, string.concat(base, "safeAddress"))
            });
        }
    }

    function _loadCustody(string memory raw) private returns (CustodyConfig memory c) {
        c.custody = vm.parseJsonAddress(raw, "$.custody.custody");
        c.treasury = vm.parseJsonAddress(raw, "$.custody.treasury");
        c.preDepositDustLimit = vm.parseJsonUint(raw, "$.custody.preDepositDustLimit");
        c.oracleQuorum = vm.parseJsonAddressArray(raw, "$.custody.oracleQuorum");
    }

    function _loadGhostBatch(string memory raw) private returns (GhostBatchRow[] memory rows) {
        uint256 n = _count(raw, "ghostBatch");
        rows = new GhostBatchRow[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat("$.ghostBatch[", vm.toString(i), "].");
            rows[i] = GhostBatchRow({
                addr: vm.parseJsonAddress(raw, string.concat(base, "address")),
                interestSd: vm.parseJsonUint(raw, string.concat(base, "interestSd")),
                note: vm.parseJsonString(raw, string.concat(base, "note"))
            });
        }
    }

    /// @notice Resolve the Safe address holding `roleName` on
    ///         `contractAddress` according to the sheet. Linear scan;
    ///         sheet is small.
    /// @return safe `address(0)` if no matching row.
    function _findRoleSafe(
        Sheet memory s,
        address contractAddress,
        string memory roleName
    ) internal pure returns (address safe) {
        bytes32 wantContract = bytes32(uint256(uint160(contractAddress)));
        bytes32 wantRole = keccak256(bytes(roleName));
        for (uint256 i = 0; i < s.roleHolders.length; i++) {
            if (bytes32(uint256(uint160(s.roleHolders[i].contractAddress))) != wantContract) continue;
            if (keccak256(bytes(s.roleHolders[i].roleName)) != wantRole) continue;
            return s.roleHolders[i].safeAddress;
        }
        return address(0);
    }
}
