// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/factory/VaultFactory.sol";
import "../../contracts/NodeELRewardVault.sol";
import "../../contracts/ValidatorWithdrawalVault.sol";

import "../mocks/PoolUtilsMock.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract VaultFactoryTest is Test {
    address staderAdmin;

    PoolUtilsMock poolUtils;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;

    function setUp() public {
        staderAdmin = vm.addr(100);
        address ethDepositAddr = vm.addr(102);
        address operator = address(500);
        
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        poolUtils = new PoolUtilsMock(address(staderConfig), operator);

        VaultFactory vfImpl = new VaultFactory();
        TransparentUpgradeableProxy vfProxy = new TransparentUpgradeableProxy(address(vfImpl), address(proxyAdmin), "");
        vaultFactory = VaultFactory(address(vfProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updatePoolUtils(address(poolUtils));
        vaultFactory.grantRole(vaultFactory.NODE_REGISTRY_CONTRACT(), address(poolUtils.nodeRegistry()));
        vm.stopPrank();
    }

    function test_initialize() public {
        assertEq(address(vaultFactory.staderConfig()), address(staderConfig));
        assertNotEq(vaultFactory.vaultProxyImplementation(), address(0));
        assertTrue(vaultFactory.hasRole(vaultFactory.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        VaultFactory vfImpl = new VaultFactory();
        TransparentUpgradeableProxy vfProxy = new TransparentUpgradeableProxy(address(vfImpl), address(proxyAdmin), "");
        VaultFactory vaultFactory2 = VaultFactory(address(vfProxy));
        vaultFactory2.initialize(staderAdmin, address(staderConfig));
    }

    function test_nodeELRewardVault_deploy() public {
        address nodeELRewardVaultImpl = address(new NodeELRewardVault());
        vm.prank(staderAdmin);
        staderConfig.updateNodeELRewardImplementation(nodeELRewardVaultImpl);

        vm.prank(address(poolUtils.nodeRegistry()));
        address payable nodeELCloneAddr = payable(vaultFactory.deployNodeELRewardVault(1, 1));

        assertNotEq(nodeELCloneAddr, nodeELRewardVaultImpl);
        assertEq(nodeELCloneAddr, vaultFactory.computeNodeELRewardVaultAddress(1, 1));

        // try to deploy again with same salt
        vm.prank(address(poolUtils.nodeRegistry()));
        vm.expectRevert();
        vaultFactory.deployNodeELRewardVault(1, 1);

        vm.prank(address(poolUtils.nodeRegistry()));
        address payable nodeELCloneAddr2 = payable(vaultFactory.deployNodeELRewardVault(1, 2));
        assertNotEq(nodeELCloneAddr, nodeELCloneAddr2);
    }

    function test_withdrawVault_deploy() public {
        address withdrawVaultImpl = address(new ValidatorWithdrawalVault());
        vm.prank(staderAdmin);
        staderConfig.updateValidatorWithdrawalVaultImplementation(withdrawVaultImpl);

        vm.prank(address(poolUtils.nodeRegistry()));
        address payable withdrawVaultClone = payable(vaultFactory.deployWithdrawVault(1, 1, 1, 1));

        assertNotEq(withdrawVaultClone, withdrawVaultImpl);
        assertEq(withdrawVaultClone, vaultFactory.computeWithdrawVaultAddress(1, 1, 1));

        // try to deploy again with same salt
        vm.prank(address(poolUtils.nodeRegistry()));
        vm.expectRevert();
        vaultFactory.deployWithdrawVault(1, 1, 1, 1);

        vm.prank(address(poolUtils.nodeRegistry()));
        address payable withdrawVaultClone2 = payable(vaultFactory.deployWithdrawVault(1, 1, 2, 1));
        assertNotEq(withdrawVaultClone, withdrawVaultClone2);
    }

    function test_getValidatorWithdrawCredential() public {
        address anyAddr = vm.addr(88393);
        bytes memory encodedBytes = abi.encodePacked(bytes1(0x01), bytes11(0x0), address(anyAddr));

        assertEq(encodedBytes, vaultFactory.getValidatorWithdrawCredential(anyAddr));
    }

    function test_updateVaultProxyAddress() public {
        address vaultProxyImpl2 = address(new VaultProxy());
        assertNotEq(vaultProxyImpl2, vaultFactory.vaultProxyImplementation());

        address nodeELClone1 = vaultFactory.computeNodeELRewardVaultAddress(1, 5);

        vm.prank(staderAdmin);
        vaultFactory.updateVaultProxyAddress(vaultProxyImpl2);

        address nodeELClone2 = vaultFactory.computeNodeELRewardVaultAddress(1, 5);

        assertNotEq(nodeELClone1, nodeELClone2);
    }

    function test_updateStaderConfig() public {
        vm.expectRevert(); // access control
        vaultFactory.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        vaultFactory.updateStaderConfig(vm.addr(203));
        assertEq(address(vaultFactory.staderConfig()), vm.addr(203));
    }
}
