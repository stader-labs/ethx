pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/VaultProxy.sol';
import '../../contracts/NodeELRewardVault.sol';
import '../../contracts/OperatorRewardsCollector.sol';
import '../../contracts/factory/VaultFactory.sol';

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
    address payable nodeELCloneAddr;
    OperatorRewardsCollector operatorRC;
    VaultFactory vaultFactory;

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

        OperatorRewardsCollector operatorRCImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRCProxy = new TransparentUpgradeableProxy(
            address(operatorRCImpl),
            address(proxyAdmin),
            ''
        );
        operatorRC = OperatorRewardsCollector(address(operatorRCProxy));
        operatorRC.initialize(staderAdmin, address(staderConfig));

        poolUtils = new PoolUtilsMock(address(staderConfig));
        NodeELRewardVault nodeELRewardVaultImpl = new NodeELRewardVault();

        VaultFactory vfImpl = new VaultFactory();
        TransparentUpgradeableProxy vfProxy = new TransparentUpgradeableProxy(address(vfImpl), address(proxyAdmin), '');
        vaultFactory = VaultFactory(address(vfProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateOperatorRewardsCollector(address(operatorRC));
        staderConfig.updateNodeELRewardImplementation(address(nodeELRewardVaultImpl));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vaultFactory.grantRole(vaultFactory.NODE_REGISTRY_CONTRACT(), address(poolUtils.nodeRegistry()));
        vm.stopPrank();

        vm.prank(address(poolUtils.nodeRegistry()));
        nodeELCloneAddr = payable(vaultFactory.deployNodeELRewardVault(poolId, operatorId));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        OperatorRewardsCollector operatorRCImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRCProxy = new TransparentUpgradeableProxy(
            address(operatorRCImpl),
            address(proxyAdmin),
            ''
        );
        OperatorRewardsCollector operatorRC2 = OperatorRewardsCollector(address(operatorRCProxy));
        operatorRC2.initialize(staderAdmin, address(staderConfig));
    }

    function test_initialise() public {
        assertTrue(VaultProxy(nodeELCloneAddr).isInitialized());

        address randomUser = vm.addr(2342);
        vm.prank(randomUser);
        vm.expectRevert(IVaultProxy.AlreadyInitialized.selector);
        VaultProxy(nodeELCloneAddr).initialise(true, poolId, operatorId, address(staderConfig));

        assertEq(address(VaultProxy(nodeELCloneAddr).staderConfig()), address(staderConfig));
        assertEq(VaultProxy(nodeELCloneAddr).owner(), staderAdmin);
        assertFalse(VaultProxy(nodeELCloneAddr).isValidatorWithdrawalVault());
        assertEq(VaultProxy(nodeELCloneAddr).poolId(), poolId);
        assertEq(VaultProxy(nodeELCloneAddr).id(), operatorId);
    }

    function test_receive(uint256 amount) public {
        address randomEOA = vm.addr(567);

        assertEq(nodeELCloneAddr.balance, 0);

        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        (bool success, ) = nodeELCloneAddr.call{value: amount}('');
        assertTrue(success);

        assertEq(nodeELCloneAddr.balance, amount);
    }

    // NOTE: used uint128 to avoid arithmetic underflow overflow in calculateRewardShare
    function test_withdraw(uint128 rewardEth) public {
        assertEq(nodeELCloneAddr.balance, 0);
        vm.expectRevert(INodeELRewardVault.NotEnoughRewardToWithdraw.selector);
        INodeELRewardVault(nodeELCloneAddr).withdraw();

        vm.assume(rewardEth > 0);
        vm.deal(nodeELCloneAddr, rewardEth); // send rewardEth to nodeELRewardVault

        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);
        address operator = address(500);
        address opRewardAddr = vm.addr(4);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        assertEq(nodeELCloneAddr.balance, rewardEth);
        assertEq(operatorRC.balances(operator), 0);

        INodeELRewardVault(nodeELCloneAddr).withdraw();

        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = poolUtils.calculateRewardShare(
            1,
            rewardEth
        );

        assertEq(address(sspm).balance, userShare);
        assertEq(address(treasury).balance, protocolShare);
        assertEq(address(opRewardAddr).balance, 0);
        assertEq(address(operatorRC).balance, operatorShare);
        assertEq(operatorRC.balances(operator), operatorShare);

        // claim by operator
        vm.mockCall(
            address(poolUtils.nodeRegistry()),
            abi.encodeWithSelector(INodeRegistry.getOperatorRewardAddress.selector),
            abi.encode(opRewardAddr)
        );

        vm.prank(operator);
        operatorRC.claim();

        assertEq(address(opRewardAddr).balance, operatorShare);
        assertEq(operatorRC.balances(operator), 0);
    }

    function test_updateStaderConfig() public {
        vm.expectRevert(IVaultProxy.CallerNotOwner.selector);
        VaultProxy(nodeELCloneAddr).updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        VaultProxy(nodeELCloneAddr).updateStaderConfig(vm.addr(203));
        assertEq(address(VaultProxy(nodeELCloneAddr).staderConfig()), vm.addr(203));
    }

    function test_updateOwner() public {
        assertEq(VaultProxy(nodeELCloneAddr).owner(), staderAdmin);
        vm.prank(staderAdmin);
        staderConfig.updateAdmin(vm.addr(203));
        VaultProxy(nodeELCloneAddr).updateOwner();
        assertEq(VaultProxy(nodeELCloneAddr).owner(), vm.addr(203));
    }
}
