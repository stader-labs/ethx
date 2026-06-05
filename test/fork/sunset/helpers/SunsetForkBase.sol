// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ActorImpersonation } from "./ActorImpersonation.sol";
import { MainnetAddresses } from "./MainnetAddresses.sol";

import { StaderStakePoolsManager } from "contracts/StaderStakePoolsManager.sol";
import { SDUtilityPool } from "contracts/SDUtilityPool.sol";
import { SocializingPool } from "contracts/SocializingPool.sol";
import { PermissionlessPool } from "contracts/PermissionlessPool.sol";
import { OperatorRewardsCollector } from "contracts/OperatorRewardsCollector.sol";
import { UserWithdrawalManager } from "contracts/UserWithdrawalManager.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IStaderOracle } from "contracts/interfaces/IStaderOracle.sol";

/// @notice Base contract for every test in the sunset fork suite.
///         Pins a mainnet fork at `FORK_BLOCK` (env, optional;
///         defaults to latest) and loads the runoff sheet once for
///         fail-fast validation. Exposes shared helpers for upgrading
///         every proxy in-place and for mocking the oracle's
///         post-decommission state.
abstract contract SunsetForkBase is ActorImpersonation {
    uint256 internal freezeBlock;

    function setUp() public virtual {
        // Prefer ETH_RPC_URL env (lets devs use any provider without
        // setting up foundry.toml rpc_endpoints credentials). Falls
        // back to the `mainnet` alias from foundry.toml.
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.rpcUrl("mainnet");

        uint256 envBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (envBlock == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, envBlock);
        }
        freezeBlock = block.number;
        _loadSheet();
    }

    /// @notice Deploy fresh implementations and call ProxyAdmin.upgrade
    ///         for all seven sunset proxies. Tests that need
    ///         post-upgrade state (`PostSweepKillSwitch`, sweep-
    ///         flavoured `EdgeCaseFailures`) call this in their setUp.
    function _upgradeAllProxies(Sheet memory s) internal {
        StaderStakePoolsManager sspmImpl = new StaderStakePoolsManager();
        SDUtilityPool sdUtilityPoolImpl = new SDUtilityPool();
        SocializingPool socializingPoolImpl = new SocializingPool();
        PermissionlessPool permissionlessPoolImpl = new PermissionlessPool();
        OperatorRewardsCollector operatorRewardsCollectorImpl = new OperatorRewardsCollector();
        UserWithdrawalManager userWithdrawalManagerImpl = new UserWithdrawalManager();

        ProxyAdmin pa = ProxyAdmin(MainnetAddresses.PROXY_ADMIN);
        _asProxyAdminOwner(s);
        pa.upgrade(ITransparentUpgradeableProxy(MainnetAddresses.SSPM), address(sspmImpl));
        pa.upgrade(ITransparentUpgradeableProxy(MainnetAddresses.SD_UTILITY_POOL), address(sdUtilityPoolImpl));
        pa.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONED),
            address(socializingPoolImpl)
        );
        pa.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.SOCIALIZING_POOL_PERMISSIONLESS),
            address(socializingPoolImpl)
        );
        pa.upgrade(ITransparentUpgradeableProxy(MainnetAddresses.PERMISSIONLESS_POOL), address(permissionlessPoolImpl));
        pa.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.OPERATOR_REWARDS_COLLECTOR),
            address(operatorRewardsCollectorImpl)
        );
        pa.upgrade(
            ITransparentUpgradeableProxy(MainnetAddresses.USER_WITHDRAWAL_MANAGER),
            address(userWithdrawalManagerImpl)
        );
        _stop();
    }

    /// @notice Simulate the post-decommission state of the StaderOracle:
    ///         `trustedNodesCount() == 0` and `isTrustedNode(any) == false`.
    ///         Used by `OracleDecommissionGateTest` and
    ///         `OpenInstantRedemptionTest` to validate gate logic in
    ///         a CI-friendly way.
    ///
    ///         Real runbook execution reads live state (the oracle
    ///         cluster is decommissioned before instant redemption is
    ///         proposed). Set `STRICT_LIVE_ORACLE=1` to skip the mock
    ///         and assert against on-chain state instead, which will
    ///         fail until the decommission lands on mainnet.
    function _simulateOracleDecommissioned() internal returns (bool mocked) {
        if (vm.envOr("STRICT_LIVE_ORACLE", uint256(0)) == 1) {
            emit log_string("STRICT_LIVE_ORACLE=1; skipping oracle decommission mock");
            return false;
        }
        vm.mockCall(
            MainnetAddresses.STADER_ORACLE,
            abi.encodeWithSelector(IStaderOracle.trustedNodesCount.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            MainnetAddresses.STADER_ORACLE,
            abi.encodeWithSelector(IStaderOracle.isTrustedNode.selector),
            abi.encode(false)
        );
        return true;
    }
}
