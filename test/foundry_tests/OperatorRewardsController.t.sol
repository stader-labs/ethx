// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/SDUtilityPool.sol';
import '../../contracts/SDIncentiveController.sol';
import '../../contracts/OperatorRewardsCollector.sol';

import '../mocks/SDCollateralMock.sol';
import '../mocks/StaderTokenMock.sol';
import '../mocks/SDIncentiveControllerMock.sol';
import '../mocks/PoolUtilsMock.sol';
import '../mocks/WETHMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract OperatorRewardsCollectorTest is Test {
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);
    event UpdatedWethAddress(address indexed weth);
    event SDWithdrawn(address indexed operator, uint256 sdAmount);
    event SDRepaid(address operator, uint256 repayAmount);

    address staderAdmin;
    address staderManager;
    address staderTreasury;

    StaderConfig staderConfig;
    SDUtilityPool sdUtilityPool;
    SDIncentiveController sdIncentiveController;
    OperatorRewardsCollector operatorRewardsCollector;
    StaderTokenMock staderToken;
    SDCollateralMock sdCollateral;
    PoolUtilsMock poolUtils;
    WETHMock weth;

    function setupAddresses() private {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        staderTreasury = vm.addr(105);
    }

    function setupMocks() private {
        staderToken = new StaderTokenMock();
        weth = new WETHMock();
        sdCollateral = new SDCollateralMock();
    }

    function setUp() public {
        setupAddresses();
        setupMocks();

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

        sdCollateral = new SDCollateralMock();
        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(staderTreasury);

        SDUtilityPool sdUtilityPoolImpl = new SDUtilityPool();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(sdUtilityPoolImpl),
            address(admin),
            ''
        );
        sdUtilityPool = SDUtilityPool(address(proxy));
        staderToken.approve(address(sdUtilityPool), 1000 ether);
        sdUtilityPool.initialize(staderAdmin, address(staderConfig));

        vm.prank(staderAdmin);
        sdUtilityPool.updateRiskConfig(70, 30, 5, 50);

        SDIncentiveController sdIncentiveControllerImpl = new SDIncentiveController();
        TransparentUpgradeableProxy sdIncentiveControllerProxy = new TransparentUpgradeableProxy(
            address(sdIncentiveControllerImpl),
            address(admin),
            ''
        );
        sdIncentiveController = SDIncentiveController(address(sdIncentiveControllerProxy));
        sdIncentiveController.initialize(staderAdmin, address(staderConfig));

        OperatorRewardsCollector operatorRewardsCollectorImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRewardsCollectorProxy = new TransparentUpgradeableProxy(
            address(operatorRewardsCollectorImpl),
            address(admin),
            ''
        );
        operatorRewardsCollector = OperatorRewardsCollector(address(operatorRewardsCollectorProxy));
        operatorRewardsCollector.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateSDIncentiveController(address(sdIncentiveController));
        staderConfig.updateSDUtilityPool(address(sdUtilityPool));
        staderConfig.updateOperatorRewardsCollector(address(operatorRewardsCollector));
        operatorRewardsCollector.updateWethAddress(address(weth));
        vm.stopPrank();
    }

    function test_Initialize() public {
        ProxyAdmin admin = new ProxyAdmin();
        OperatorRewardsCollector operatorRewardsCollectorImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRewardsCollectorProxy = new TransparentUpgradeableProxy(
            address(operatorRewardsCollectorImpl),
            address(admin),
            ''
        );
        operatorRewardsCollector = OperatorRewardsCollector(address(operatorRewardsCollectorProxy));
        vm.expectEmit();
        emit UpdatedStaderConfig(address(staderConfig));
        operatorRewardsCollector.initialize(staderAdmin, address(staderConfig));
    }

    function test_VerifyInitialize() public {
        assertEq(address(operatorRewardsCollector.staderConfig()), address(staderConfig));
        assertTrue(operatorRewardsCollector.hasRole(sdIncentiveController.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_DepositFor(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        vm.expectEmit(true, true, true, true, address(operatorRewardsCollector));
        emit DepositedFor(address(this), staderManager, amount);
        operatorRewardsCollector.depositFor{value: amount}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        vm.expectEmit(true, true, true, true, address(operatorRewardsCollector));
        emit DepositedFor(address(this), staderManager, 0 ether);
        operatorRewardsCollector.depositFor{value: 0 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
    }

    function test_Claim(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        operatorRewardsCollector.depositFor{value: amount}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0);
        vm.stopPrank();
    }

    function test_claimLiquidationZeroAmount(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        operatorRewardsCollector.depositFor{value: amount}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        operatorRewardsCollector.claimLiquidation(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
    }

    function test_claimLiquidation(uint16 randomSeed) public {
        vm.assume(randomSeed > 1);
        uint256 utilizeAmount = 1e22;

        address operator = vm.addr(randomSeed);
        address liquidator = vm.addr(randomSeed - 1);

        operatorRewardsCollector.depositFor{value: 100 ether}(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );

        vm.roll(block.number + 1900000000);

        UserData memory userData = sdUtilityPool.getUserData(operator);
        staderToken.transfer(liquidator, userData.totalInterestSD);
        vm.startPrank(liquidator);
        staderToken.approve(address(sdUtilityPool), userData.totalInterestSD);
        assertEq(operatorRewardsCollector.withdrawableInEth(operator), 0);
        sdUtilityPool.liquidationCall(operator);
        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);
        vm.stopPrank();

        operatorRewardsCollector.claimLiquidation(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether - operatorLiquidation.totalAmountInEth);

        vm.startPrank(operator);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator), 0);
        vm.stopPrank();
    }

    function test_claimLiquidationLastValidator(uint16 randomSeed) public {
        vm.assume(randomSeed > 1);
        uint256 utilizeAmount = 1e22;

        address operator = vm.addr(randomSeed);
        address liquidator = vm.addr(randomSeed - 1);

        operatorRewardsCollector.depositFor{value: 100 ether}(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.getOperatorInfo.selector),
            abi.encode(0, 0, 0)
        );

        vm.roll(block.number + 1900000000);

        UserData memory userData = sdUtilityPool.getUserData(operator);
        staderToken.transfer(liquidator, userData.totalInterestSD);
        vm.startPrank(liquidator);
        staderToken.approve(address(sdUtilityPool), userData.totalInterestSD);
        assertEq(operatorRewardsCollector.withdrawableInEth(operator), 0);
        sdUtilityPool.liquidationCall(operator);
        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);
        vm.stopPrank();

        operatorRewardsCollector.claimLiquidation(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether - operatorLiquidation.totalAmountInEth);

        vm.startPrank(operator);
        vm.expectEmit();
        emit SDRepaid(operator, utilizeAmount);
        vm.expectEmit();
        emit SDWithdrawn(operator, utilizeAmount);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator), 0);
        vm.stopPrank();
    }

    function test_ClaimWithoutDeposit() public {
        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0 ether);
        vm.stopPrank();
    }

    function test_FullDepositWithdrawalCycle() public {
        uint256 depositAmount = 50 ether;
        operatorRewardsCollector.depositFor{value: depositAmount}(staderManager);

        // Simulate some earnings
        vm.roll(block.number + 100);

        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0 ether, 'Balance should be zero after claim');
        vm.stopPrank();
    }

    function test_MultipleOperatorsDepositAndClaim() public {
        address operator1 = vm.addr(107);
        address operator2 = vm.addr(108);
        uint256 depositAmount1 = 30 ether;
        uint256 depositAmount2 = 40 ether;

        operatorRewardsCollector.depositFor{value: depositAmount1}(operator1);
        operatorRewardsCollector.depositFor{value: depositAmount2}(operator2);

        vm.startPrank(operator1);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator1), 0 ether, 'Operator1 balance should be zero after claim');
        vm.stopPrank();

        vm.startPrank(operator2);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator2), 0 ether, 'Operator2 balance should be zero after claim');
        vm.stopPrank();
    }

    function test_UpdateWETHAddress() public {
        address newWethAddress = vm.addr(109);

        vm.startPrank(staderAdmin);
        operatorRewardsCollector.updateWethAddress(newWethAddress);
        assertEq(address(operatorRewardsCollector.weth()), newWethAddress, 'WETH address should be updated');
        vm.stopPrank();

        // Test for unauthorized access
        address unauthorizedUser = vm.addr(110);
        address newWethAddress2 = vm.addr(111);
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            'AccessControl: account 0xb961768b578514debf079017ff78c47b0a6adbf6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000'
        );
        operatorRewardsCollector.updateWethAddress(newWethAddress2);
        vm.stopPrank();

        assertNotEq(address(operatorRewardsCollector.weth()), newWethAddress2, 'WETH address should not be updated');
    }

    function test_MultipleDepositsAndTotalBalance(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 < 1000e18 && amount2 < 1000e18);

        operatorRewardsCollector.depositFor{value: amount1}(staderManager);
        operatorRewardsCollector.depositFor{value: amount2}(staderManager);
        assertEq(
            operatorRewardsCollector.balances(staderManager),
            amount1 + amount2,
            'Total balance should be the sum of all deposits'
        );
    }

    function test_UpdateStaderConfig(uint16 randomSeed) public {
        vm.assume(randomSeed > 0);
        address inputAddr = vm.addr(randomSeed);
        vm.expectRevert();
        operatorRewardsCollector.updateStaderConfig(inputAddr);
        vm.startPrank(staderAdmin);
        vm.expectRevert(UtilLib.ZeroAddress.selector);
        operatorRewardsCollector.updateStaderConfig(address(0));
        operatorRewardsCollector.updateStaderConfig(inputAddr);
        assertEq(address(operatorRewardsCollector.staderConfig()), inputAddr);
    }
}
