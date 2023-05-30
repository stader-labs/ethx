pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/VaultProxy.sol';
import '../../contracts/NodeELRewardVault.sol';
import '../../contracts/OperatorRewardsCollector.sol';

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
    VaultProxy nodeELRewardVault;
    OperatorRewardsCollector operatorRC;

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

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateOperatorRewardsCollector(address(operatorRC));
        staderConfig.updateNodeELRewardImplementation(address(nodeELRewardVaultImpl));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        nodeELRewardVault = new VaultProxy();
        nodeELRewardVault.initialise(false, poolId, operatorId, address(staderConfig));
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
        assertTrue(nodeELRewardVault.isInitialized());

        address randomUser = vm.addr(2342);
        vm.prank(randomUser);
        vm.expectRevert(IVaultProxy.AlreadyInitialized.selector);
        nodeELRewardVault.initialise(true, poolId, operatorId, address(staderConfig));

        assertEq(address(nodeELRewardVault.staderConfig()), address(staderConfig));
        assertEq(nodeELRewardVault.owner(), staderAdmin);
        assertFalse(nodeELRewardVault.isValidatorWithdrawalVault());
        assertEq(nodeELRewardVault.poolId(), poolId);
        assertEq(nodeELRewardVault.id(), operatorId);
    }

    function test_receive(uint64 randomPrivateKey, uint256 amount) public {
        vm.assume(randomPrivateKey > 0);
        address randomEOA = vm.addr(randomPrivateKey);

        assertEq(address(nodeELRewardVault).balance, 0);
        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        // vm.expectEmit(true, true, true, true);
        // emit nodeELRewardVault.ETHReceived(randomEOA, amount); // TODO: error: unable to access events
        (bool success, ) = payable(nodeELRewardVault).call{value: amount}('');
        assertTrue(success);
        assertEq(address(nodeELRewardVault).balance, amount);
    }

    // NOTE: used uint128 to avoid arithmetic underflow overflow in calculateRewardShare
    function test_withdraw(uint128 rewardEth) public {
        assertEq(address(nodeELRewardVault).balance, 0);
        vm.expectRevert(INodeELRewardVault.NotEnoughRewardToWithdraw.selector);
        INodeELRewardVault(address(nodeELRewardVault)).withdraw();

        vm.assume(rewardEth > 0);
        vm.deal(address(nodeELRewardVault), rewardEth); // send rewardEth to nodeELRewardVault

        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);
        address operator = address(500);
        address opRewardAddr = vm.addr(4);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        assertEq(address(nodeELRewardVault).balance, rewardEth);
        assertEq(operatorRC.balances(operator), 0);

        INodeELRewardVault(address(nodeELRewardVault)).withdraw();

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
        nodeELRewardVault.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        nodeELRewardVault.updateStaderConfig(vm.addr(203));
        assertEq(address(nodeELRewardVault.staderConfig()), vm.addr(203));
    }

    function test_updateOwner() public {
        vm.expectRevert(IVaultProxy.CallerNotOwner.selector);
        nodeELRewardVault.updateOwner(vm.addr(203));

        assertEq(nodeELRewardVault.owner(), staderAdmin);
        vm.prank(staderAdmin);
        nodeELRewardVault.updateOwner(vm.addr(203));
        assertEq(nodeELRewardVault.owner(), vm.addr(203));
    }
}
