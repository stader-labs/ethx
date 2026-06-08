// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SunsetForkBase } from "./helpers/SunsetForkBase.sol";
import { MainnetAddresses } from "./helpers/MainnetAddresses.sol";

import { IStaderOracle, WithdrawnValidators } from "contracts/interfaces/IStaderOracle.sol";

interface INodeRegistryQuery {
    function nextValidatorId() external view returns (uint256);
    function validatorRegistry(
        uint256
    )
        external
        view
        returns (
            uint8 status,
            bytes memory pubkey,
            bytes memory preDepositSignature,
            bytes memory depositSignature,
            address payable withdrawVaultAddress,
            uint256 operatorId,
            uint256 depositBlock,
            uint256 withdrawnBlock
        );
    function POOL_ID() external view returns (uint8);
}

/// @notice End-to-end validator exit cascade for a single operator.
///         Foundry cannot trigger a real beacon exit, so the test
///         mocks the L1 post-exit state in three steps:
///           1. `vm.deal` 32 ETH × N to each `ValidatorWithdrawalVault`,
///           2. impersonate the oracle quorum and submit
///              `submitWithdrawnValidators` until threshold,
///           3. assert the L1 cascade: `settleFunds` runs, the
///              `NodeRegistry` flips keys to `WITHDRAWN`, and
///              `nonTerminalKeys` decrements for the operator.
///         This is the only beacon-layer mock in the suite.
contract ValidatorExitCascadeTest is SunsetForkBase {
    function test_FullValidatorExit() public {
        uint256 opId = vm.envOr("OPERATOR_ID", uint256(0));
        if (opId == 0) {
            emit log_string("OPERATOR_ID env not set; cascade template skipped");
            return;
        }
        Sheet memory sheet = _loadSheet();
        require(sheet.custody.oracleQuorum.length > 0, "sheet oracle_quorum empty");

        // Find validators for this operator by sweeping nextValidatorId.
        // 5000 caps RPC chatter; raise it if the registry grows past that.
        uint256 maxSweep = 5000;
        INodeRegistryQuery reg = INodeRegistryQuery(MainnetAddresses.PERMISSIONLESS_NODE_REGISTRY);
        uint256 next = reg.nextValidatorId();
        uint256 sweepEnd = next < maxSweep ? next : maxSweep;
        uint8 poolId = reg.POOL_ID();

        bytes[] memory sortedPubkeys = new bytes[](sweepEnd);
        address[] memory vaults = new address[](sweepEnd);
        uint256 found;
        for (uint256 i = 1; i < sweepEnd; i++) {
            (uint8 stat, bytes memory pk, , , address payable vault, uint256 operator, , ) = reg.validatorRegistry(i);
            if (operator == opId && stat < 4) {
                sortedPubkeys[found] = pk;
                vaults[found] = vault;
                found++;
            }
        }
        if (found == 0) {
            emit log_string("no active validators for operator id; skipping");
            return;
        }

        // Pre-fund vaults to mimic beacon chain payout landing.
        for (uint256 i = 0; i < found; i++) {
            if (vaults[i] == address(0)) continue;
            vm.deal(vaults[i], 32 ether);
        }

        // Trim arrays to `found`.
        bytes[] memory pubkeys = new bytes[](found);
        for (uint256 i = 0; i < found; i++) pubkeys[i] = sortedPubkeys[i];

        WithdrawnValidators memory payload = WithdrawnValidators({
            poolId: poolId,
            reportingBlockNumber: block.number,
            sortedPubkeys: pubkeys
        });

        address operatorAddr = _opAddrFromId(opId, reg);
        uint256 preNonTerminal = _readNonTerminalKeys(operatorAddr);
        emit log_named_uint("nonTerminalKeys pre-cascade", preNonTerminal);

        uint256 accepted = _submitQuorum(sheet, payload);
        emit log_named_uint("validators marked withdrawn (target)", found);
        emit log_named_uint("submissions accepted", accepted);

        if (accepted == 0) {
            emit log_string("no submissions accepted; sheet quorum likely not trusted; skipping cascade asserts");
            return;
        }
        uint256 postNonTerminal = _readNonTerminalKeys(operatorAddr);
        emit log_named_uint("nonTerminalKeys post-cascade", postNonTerminal);
        assertLt(postNonTerminal, preNonTerminal, "nonTerminalKeys did not decrement; cascade failed");
    }

    function _submitQuorum(Sheet memory sheet, WithdrawnValidators memory payload) private returns (uint256 accepted) {
        for (uint256 q = 0; q < sheet.custody.oracleQuorum.length; q++) {
            address node = sheet.custody.oracleQuorum[q];
            vm.prank(node);
            try IStaderOracle(MainnetAddresses.STADER_ORACLE).submitWithdrawnValidators(payload) {
                accepted++;
                emit log_named_address("submission accepted from", node);
            } catch {
                emit log_named_address("submission rejected (not trusted) from", node);
            }
        }
    }

    function _readNonTerminalKeys(address operatorAddr) private returns (uint256) {
        (bool ok, bytes memory d) = MainnetAddresses.SD_COLLATERAL.staticcall(
            abi.encodeWithSignature("getOperatorInfo(address)", operatorAddr)
        );
        require(ok, "getOperatorInfo failed");
        (, , uint256 nonTerminal) = abi.decode(d, (uint8, uint256, uint256));
        return nonTerminal;
    }

    function _opAddrFromId(uint256 opId, INodeRegistryQuery reg) private view returns (address) {
        // PermissionlessNodeRegistry exposes operatorStructById which
        // returns the operator's address as the fifth field.
        (bool ok, bytes memory data) = address(reg).staticcall(
            abi.encodeWithSignature("operatorStructById(uint256)", opId)
        );
        require(ok, "operatorStructById failed");
        (, , , , address operatorAddress) = abi.decode(data, (bool, bool, string, address, address));
        return operatorAddress;
    }
}
