pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/NodeELRewardVault.sol';

import '../mocks/PoolUtilsMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract NodeELRewardVaultTest is Test {
    address staderAdmin;
    address staderManager;
    address staderTreasury;
    PoolUtilsMock poolUtils;

    uint8 poolId;
    uint256 operatorId;

    StaderConfig staderConfig;
    NodeELRewardVault nodeELRewardVault;

    function setUp() public {
        poolId = 1;
        operatorId = 1;

        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
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

        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

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
        UtilLib.onlyManagerRole(staderManager, staderConfig);
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

    // NOTE: used uint128 to avoid arithmetic underflow overflow in calculateRewardShare
    function test_withdraw(uint128 rewardEth) public {
        assertEq(address(nodeELRewardVault).balance, 0);
        vm.expectRevert(INodeELRewardVault.NotEnoughRewardToWithdraw.selector);
        nodeELRewardVault.withdraw();

        vm.assume(rewardEth > 0);
        vm.deal(address(nodeELRewardVault), rewardEth); // send rewardEth to nodeELRewardVault

        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);
        address opRewardAddr = vm.addr(4);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        vm.mockCall(
            address(poolUtils.nodeRegistry()),
            abi.encodeWithSelector(INodeRegistry.getOperatorRewardAddress.selector),
            abi.encode(opRewardAddr)
        );

        assertEq(address(nodeELRewardVault).balance, rewardEth);

        nodeELRewardVault.withdraw();

        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = poolUtils.calculateRewardShare(
            1,
            rewardEth
        );

        assertEq(address(sspm).balance, userShare);
        assertEq(address(treasury).balance, protocolShare);
        assertEq(address(opRewardAddr).balance, operatorShare);
    }

    function test_updateStaderConfig() public {
        // not staderAdmin
        vm.expectRevert();
        nodeELRewardVault.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        nodeELRewardVault.updateStaderConfig(vm.addr(203));
        assertEq(address(nodeELRewardVault.staderConfig()), vm.addr(203));
    }
}
