pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/VaultProxy.sol';
import '../../contracts/ValidatorWithdrawalVault.sol';
import '../../contracts/OperatorRewardsCollector.sol';

import '../mocks/PoolUtilsMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract ValidatorWithdrawalVaultTest is Test {
    address staderAdmin;
    address staderManager;
    address staderTreasury;
    PoolUtilsMock poolUtils;

    uint8 poolId;
    uint256 validatorId;

    StaderConfig staderConfig;
    VaultProxy withdrawVault;
    OperatorRewardsCollector operatorRC;

    function setUp() public {
        poolId = 1;
        validatorId = 1;

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
        ValidatorWithdrawalVault withdrawVaultImpl = new ValidatorWithdrawalVault();

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateOperatorRewardsCollector(address(operatorRC));
        staderConfig.updateValidatorWithdrawalVaultImplementation(address(withdrawVaultImpl));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        withdrawVault = new VaultProxy();
        withdrawVault.initialise(true, poolId, validatorId, address(staderConfig));
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

        VaultProxy withdrawVault2 = new VaultProxy();
        withdrawVault2.initialise(true, poolId, validatorId, address(staderConfig));
    }

    function test_initialise() public {
        assertTrue(withdrawVault.isInitialized());

        address randomUser = vm.addr(2342);
        vm.prank(randomUser);
        vm.expectRevert(IVaultProxy.AlreadyInitialized.selector);
        withdrawVault.initialise(true, poolId, validatorId, address(staderConfig));

        assertEq(address(withdrawVault.staderConfig()), address(staderConfig));
        assertEq(withdrawVault.owner(), staderAdmin);
        assertTrue(withdrawVault.isValidatorWithdrawalVault());
        assertEq(withdrawVault.poolId(), poolId);
        assertEq(withdrawVault.id(), validatorId);
    }

    function test_receive(uint64 randomPrivateKey, uint256 amount) public {
        vm.assume(randomPrivateKey > 0);
        address randomEOA = vm.addr(randomPrivateKey);

        assertEq(address(withdrawVault).balance, 0);
        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        (bool success, ) = payable(withdrawVault).call{value: amount}('');
        assertTrue(success);
        assertEq(address(withdrawVault).balance, amount);
    }

    // NOTE: used uint128 to avoid arithmetic underflow overflow in calculateRewardShare
    function test_distributeRewards(uint128 rewardEth) public {
        assertEq(address(withdrawVault).balance, 0);
        vm.expectRevert(IValidatorWithdrawalVault.NotEnoughRewardToDistribute.selector);
        IValidatorWithdrawalVault(address(withdrawVault)).distributeRewards();

        vm.prank(staderManager);
        staderConfig.updateRewardsThreshold(8 ether);

        vm.assume(rewardEth > 0);
        vm.deal(address(withdrawVault), rewardEth); // send rewardEth to nodeELRewardVault

        if (rewardEth > 8 ether) {
            vm.expectRevert(IValidatorWithdrawalVault.InvalidRewardAmount.selector);
            IValidatorWithdrawalVault(address(withdrawVault)).distributeRewards();

            // add case when operator is calling
            return;
        }
        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);
        address operator = address(500);
        address opRewardAddr = vm.addr(4);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        assertEq(address(withdrawVault).balance, rewardEth);
        assertEq(operatorRC.balances(operator), 0);

        IValidatorWithdrawalVault(address(withdrawVault)).distributeRewards();

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

    function test_settleFunds() public {
        vm.expectRevert(IValidatorWithdrawalVault.CallerNotNodeRegistryContract.selector);
        IValidatorWithdrawalVault(address(withdrawVault)).settleFunds();
    }

    function test_updateStaderConfig() public {
        vm.expectRevert(IVaultProxy.CallerNotOwner.selector);
        withdrawVault.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        withdrawVault.updateStaderConfig(vm.addr(203));
        assertEq(address(withdrawVault.staderConfig()), vm.addr(203));
    }

    function test_updateOwner() public {
        vm.expectRevert(IVaultProxy.CallerNotOwner.selector);
        withdrawVault.updateOwner(vm.addr(203));

        assertEq(withdrawVault.owner(), staderAdmin);
        vm.prank(staderAdmin);
        withdrawVault.updateOwner(vm.addr(203));
        assertEq(withdrawVault.owner(), vm.addr(203));
    }
}
