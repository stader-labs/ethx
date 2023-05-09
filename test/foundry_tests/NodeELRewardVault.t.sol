pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/NodeELRewardVault.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract NodeELRewardVaultTest is Test {
    address staderAdmin;
    uint8 poolId;
    uint256 operatorId;

    StaderConfig staderConfig;
    NodeELRewardVault nodeELRewardVault;

    function setUp() public {
        poolId = 1;
        operatorId = 1;

        staderAdmin = vm.addr(100);
        address ethDepositAddr = vm.addr(102);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);
        vm.prank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);

        NodeELRewardVault nodeELRewardVaultImpl = new NodeELRewardVault();
        TransparentUpgradeableProxy nodeELRewardVaultProxy = new TransparentUpgradeableProxy(
            address(nodeELRewardVaultImpl),
            address(proxyAdmin),
            ''
        );
        nodeELRewardVault = NodeELRewardVault(payable(nodeELRewardVaultProxy));
        nodeELRewardVault.initialize(poolId, operatorId, address(staderConfig));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        NodeELRewardVault nodeELRewardVaultImpl = new NodeELRewardVault();
        TransparentUpgradeableProxy nodeELRewardVaultProxy = new TransparentUpgradeableProxy(
            address(nodeELRewardVaultImpl),
            address(proxyAdmin),
            ''
        );
        NodeELRewardVault nodeELRewardVault2 = NodeELRewardVault(payable(nodeELRewardVaultProxy));
        nodeELRewardVault2.initialize(poolId, operatorId, address(staderConfig));
    }

    function test_nodeELRewardVaultInitialize() public {
        assertEq(address(nodeELRewardVault.staderConfig()), address(staderConfig));
        assertTrue(nodeELRewardVault.hasRole(nodeELRewardVault.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertEq(nodeELRewardVault.poolId(), poolId);
        assertEq(nodeELRewardVault.operatorId(), operatorId);
    }

    function test_receive(uint64 randomPrivateKey, uint256 amount) public {
        vm.assume(randomPrivateKey > 0);
        address randomEOA = vm.addr(randomPrivateKey);

        assertEq(address(nodeELRewardVault).balance, 0);
        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        // vm.expectEmit(true, true, true, true);
        // emit nodeELRewardVault.ETHReceived(randomEOA, amount); // TODO: error: unable to access events
        payable(nodeELRewardVault).call{value: amount}('');

        assertEq(address(nodeELRewardVault).balance, amount);
    }
}
