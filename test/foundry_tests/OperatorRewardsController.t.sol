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

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract OperatorRewardsCollectorTest is Test {
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

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);
        staderTreasury = vm.addr(105);

        staderToken = new StaderTokenMock();
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
        operatorRewardsCollector.initialize(staderAdmin, address(staderConfig));
    }

    function test_VerifyInitialize() public {
        assertEq(address(operatorRewardsCollector.staderConfig()), address(staderConfig));
        assertTrue(operatorRewardsCollector.hasRole(sdIncentiveController.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_DepositFor() public {
        operatorRewardsCollector.depositFor{value: 100 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);

        operatorRewardsCollector.depositFor{value: 0 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);
    }

    function test_Claim() public {
        operatorRewardsCollector.depositFor{value: 100 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);

        operatorRewardsCollector.claimFor(staderManager, 0);
        assertEq(operatorRewardsCollector.balances(staderManager), 0 ether);

        operatorRewardsCollector.depositFor{value: 100 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);

        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0 ether);
        vm.stopPrank();

        operatorRewardsCollector.depositFor{value: 100 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);

        operatorRewardsCollector.claimFor(staderManager, 50 ether);
        assertEq(operatorRewardsCollector.balances(staderManager), 50 ether);
    }

    function test_claimLiquidation() public {
        operatorRewardsCollector.depositFor{value: 100 ether}(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);

        operatorRewardsCollector.claimLiquidation(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), 100 ether);
    }
}
