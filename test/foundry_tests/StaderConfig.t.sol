pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderConfigTest is Test {
    address staderAdmin;
    address staderManager;
    address staderOperator;

    StaderConfig staderConfig;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        staderOperator = vm.addr(103);
        address ethDepositAddr = vm.addr(102);

        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        vm.startPrank(staderAdmin);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), staderOperator);
        vm.stopPrank();
    }

    function test_initialize() public {
        assertEq(staderConfig.getStakedEthPerNode(), 32 ether);
        assertEq(staderConfig.getPreDepositSize(), 1 ether);
        assertEq(staderConfig.getFullDepositSize(), 31 ether);
        assertEq(staderConfig.getTotalFee(), 10000);
        assertEq(staderConfig.getDecimals(), 1e18);
        assertEq(staderConfig.getOperatorMaxNameLength(), 255);
        assertEq(staderConfig.getMinDepositAmount(), 1e14);
        assertEq(staderConfig.getMaxDepositAmount(), 10000 ether);
        assertEq(staderConfig.getMinWithdrawAmount(), 1e14);
        assertEq(staderConfig.getMaxWithdrawAmount(), 10000 ether);
        assertEq(staderConfig.getWithdrawnKeyBatchSize(), 50);
        assertEq(staderConfig.getMinBlockDelayToFinalizeWithdrawRequest(), 600);
        assertEq(staderConfig.getETHDepositContract(), vm.addr(102));
        assertTrue(staderConfig.hasRole(staderConfig.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertTrue(staderConfig.onlyManagerRole(staderManager));
        assertTrue(staderConfig.onlyOperatorRole(staderOperator));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        StaderConfig staderConfig2 = StaderConfig(address(configProxy));
        staderConfig2.initialize(staderAdmin, vm.addr(102));
    }

    function test_variable_setters() public {
        assertEq(staderConfig.getSocializingPoolCycleDuration(), 0);
        assertEq(staderConfig.getSocializingPoolOptInCoolingPeriod(), 0);
        assertEq(staderConfig.getRewardsThreshold(), 0);
        assertEq(staderConfig.getMinBlockDelayToFinalizeWithdrawRequest(), 600);
        assertEq(staderConfig.getWithdrawnKeyBatchSize(), 50);

        vm.startPrank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(1011);
        staderConfig.updateSocializingPoolOptInCoolingPeriod(2011);
        staderConfig.updateRewardsThreshold(702);

        vm.expectRevert(UtilLib.ZeroAddress.selector);
        staderConfig.updateStaderTreasury(address(0));

        staderConfig.updateStaderTreasury(vm.addr(7769));

        vm.expectRevert(IStaderConfig.IndenticalValue.selector);
        staderConfig.updateStaderTreasury(vm.addr(7769));

        vm.stopPrank();

        vm.startPrank(staderAdmin);
        staderConfig.updateMinBlockDelayToFinalizeWithdrawRequest(685);
        vm.stopPrank();

        vm.startPrank(staderOperator);
        staderConfig.updateWithdrawnKeysBatchSize(77);
        vm.stopPrank();

        assertEq(staderConfig.getSocializingPoolCycleDuration(), 1011);
        assertEq(staderConfig.getSocializingPoolOptInCoolingPeriod(), 2011);
        assertEq(staderConfig.getRewardsThreshold(), 702);
        assertEq(staderConfig.getMinBlockDelayToFinalizeWithdrawRequest(), 685);
        assertEq(staderConfig.getWithdrawnKeyBatchSize(), 77);
    }

    function test_contract_setters() public {
        assertEq(staderConfig.getPoolUtils(), address(0));
        assertEq(staderConfig.getPoolSelector(), address(0));
        assertEq(staderConfig.getSDCollateral(), address(0));
        assertEq(staderConfig.getOperatorRewardsCollector(), address(0));
        assertEq(staderConfig.getVaultFactory(), address(0));
        assertEq(staderConfig.getAuctionContract(), address(0));
        assertEq(staderConfig.getStaderOracle(), address(0));
        assertEq(staderConfig.getPenaltyContract(), address(0));
        assertEq(staderConfig.getPenaltyContract(), address(0));
        assertEq(staderConfig.getPermissionedPool(), address(0));
        assertEq(staderConfig.getStakePoolManager(), address(0));
        assertEq(staderConfig.getPermissionlessPool(), address(0));
        assertEq(staderConfig.getUserWithdrawManager(), address(0));
        assertEq(staderConfig.getStaderInsuranceFund(), address(0));
        assertEq(staderConfig.getPermissionedNodeRegistry(), address(0));
        assertEq(staderConfig.getPermissionlessNodeRegistry(), address(0));
        assertEq(staderConfig.getPermissionlessNodeRegistry(), address(0));
        assertEq(staderConfig.getPermissionedSocializingPool(), address(0));
        assertEq(staderConfig.getPermissionlessSocializingPool(), address(0));
        assertEq(staderConfig.getNodeELRewardVaultImplementation(), address(0));
        assertEq(staderConfig.getValidatorWithdrawalVaultImplementation(), address(0));
        assertEq(staderConfig.getETHBalancePORFeedProxy(), address(0));
        assertEq(staderConfig.getETHXSupplyPORFeedProxy(), address(0));
        assertEq(staderConfig.getStaderToken(), address(0));
        assertEq(staderConfig.getETHxToken(), address(0));

        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(vm.addr(233));
        staderConfig.updatePoolSelector(vm.addr(456));
        staderConfig.updateSDCollateral(vm.addr(556));
        staderConfig.updateOperatorRewardsCollector(vm.addr(5856));
        staderConfig.updateVaultFactory(vm.addr(1123));
        staderConfig.updateAuctionContract(vm.addr(66678));
        staderConfig.updateStaderOracle(vm.addr(8845));
        staderConfig.updatePenaltyContract(vm.addr(7867));
        staderConfig.updatePermissionedPool(vm.addr(9871));
        staderConfig.updateStakePoolManager(vm.addr(1871));
        staderConfig.updatePermissionlessPool(vm.addr(2243));
        staderConfig.updateUserWithdrawManager(vm.addr(1167));
        staderConfig.updateStaderInsuranceFund(vm.addr(3421));
        staderConfig.updatePermissionedNodeRegistry(vm.addr(4421));
        staderConfig.updatePermissionlessNodeRegistry(vm.addr(4425));
        staderConfig.updatePermissionedSocializingPool(vm.addr(6512));
        staderConfig.updatePermissionlessSocializingPool(vm.addr(6512));
        staderConfig.updateNodeELRewardImplementation(vm.addr(1111));
        staderConfig.updateValidatorWithdrawalVaultImplementation(vm.addr(2222));
        staderConfig.updateETHBalancePORFeedProxy(vm.addr(3217));
        staderConfig.updateETHXSupplyPORFeedProxy(vm.addr(3218));
        staderConfig.updateStaderToken(vm.addr(6783));
        staderConfig.updateETHxToken(vm.addr(9098));

        vm.expectRevert(IStaderConfig.IndenticalValue.selector);
        staderConfig.updatePenaltyContract(vm.addr(7867));

        vm.expectRevert(IStaderConfig.IndenticalValue.selector);
        staderConfig.updateETHxToken(vm.addr(9098));

        vm.stopPrank();

        assertEq(staderConfig.getPoolUtils(), vm.addr(233));
        assertEq(staderConfig.getPoolSelector(), vm.addr(456));
        assertEq(staderConfig.getSDCollateral(), vm.addr(556));
        assertEq(staderConfig.getOperatorRewardsCollector(), vm.addr(5856));
        assertEq(staderConfig.getVaultFactory(), vm.addr(1123));
        assertEq(staderConfig.getAuctionContract(), vm.addr(66678));
        assertEq(staderConfig.getStaderOracle(), vm.addr(8845));
        assertEq(staderConfig.getPenaltyContract(), vm.addr(7867));
        assertEq(staderConfig.getPermissionedPool(), vm.addr(9871));
        assertEq(staderConfig.getStakePoolManager(), vm.addr(1871));
        assertEq(staderConfig.getPermissionlessPool(), vm.addr(2243));
        assertEq(staderConfig.getUserWithdrawManager(), vm.addr(1167));
        assertEq(staderConfig.getStaderInsuranceFund(), vm.addr(3421));
        assertEq(staderConfig.getPermissionedNodeRegistry(), vm.addr(4421));
        assertEq(staderConfig.getPermissionlessNodeRegistry(), vm.addr(4425));
        assertEq(staderConfig.getPermissionedSocializingPool(), vm.addr(6512));
        assertEq(staderConfig.getPermissionlessSocializingPool(), vm.addr(6512));
        assertEq(staderConfig.getNodeELRewardVaultImplementation(), vm.addr(1111));
        assertEq(staderConfig.getValidatorWithdrawalVaultImplementation(), vm.addr(2222));
        assertEq(staderConfig.getETHBalancePORFeedProxy(), vm.addr(3217));
        assertEq(staderConfig.getETHXSupplyPORFeedProxy(), vm.addr(3218));
        assertEq(staderConfig.getStaderToken(), vm.addr(6783));
        assertEq(staderConfig.getETHxToken(), vm.addr(9098));
    }

    function test_depositAmount() public {
        assertEq(staderConfig.getMinDepositAmount(), 1e14);
        assertEq(staderConfig.getMaxDepositAmount(), 10000 ether);
        assertEq(staderConfig.getMinWithdrawAmount(), 1e14);
        assertEq(staderConfig.getMaxWithdrawAmount(), 10000 ether);

        vm.startPrank(staderManager);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMinDepositAmount(0);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMaxDepositAmount(0);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMaxDepositAmount(1e13);

        vm.stopPrank();

        vm.startPrank(staderAdmin);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMinWithdrawAmount(0);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMaxWithdrawAmount(0);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMinWithdrawAmount(10001 ether);

        vm.expectRevert(IStaderConfig.IndenticalValue.selector);
        staderConfig.updateMinWithdrawAmount(1e14);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMinWithdrawAmount(1e15);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMaxWithdrawAmount(1e13);

        vm.expectRevert(IStaderConfig.InvalidLimits.selector);
        staderConfig.updateMaxWithdrawAmount(9999);

        staderConfig.updateMinWithdrawAmount(1);
        staderConfig.updateMaxWithdrawAmount(10001 ether);
        vm.stopPrank();

        vm.prank(staderManager);
        staderConfig.updateMinDepositAmount(1e16);

        vm.prank(staderManager);
        staderConfig.updateMaxDepositAmount(9999 ether);

        assertEq(staderConfig.getMinDepositAmount(), 1e16);
        assertEq(staderConfig.getMaxDepositAmount(), 9999 ether);
        assertEq(staderConfig.getMinWithdrawAmount(), 1);
        assertEq(staderConfig.getMaxWithdrawAmount(), 10001 ether);
    }
}
