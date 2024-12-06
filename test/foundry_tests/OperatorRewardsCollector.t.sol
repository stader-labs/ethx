// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Test } from "forge-std/Test.sol";

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/SDUtilityPool.sol";
import "../../contracts/SDIncentiveController.sol";
import "../../contracts/OperatorRewardsCollector.sol";

import "../mocks/SDCollateralMock.sol";
import "../mocks/StaderTokenMock.sol";
import "../mocks/SDIncentiveControllerMock.sol";
import "../mocks/PoolUtilsMock.sol";
import "../mocks/StaderOracleMock.sol";
import "../mocks/WETHMock.sol";

import { PermissionlessNodeRegistryMock } from "../mocks/PermissionlessNodeRegistryMock.sol";

contract OperatorRewardsCollectorTest is Test {
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);
    event UpdatedWethAddress(address indexed weth);
    event SDWithdrawn(address indexed operator, uint256 sdAmount);
    event SDRepaid(address operator, uint256 repayAmount);

    error InsufficientBalance();

    address staderAdmin;
    address staderManager;
    address staderTreasury;

    StaderConfig staderConfig;
    SDUtilityPool sdUtilityPool;
    SDIncentiveController sdIncentiveController;
    OperatorRewardsCollector operatorRewardsCollector;
    StaderTokenMock staderToken;
    StaderOracleMock staderOracle;
    PoolUtilsMock poolUtils;
    WETHMock weth;

    address private sdCollateralMock;
    address private permissionlessNodeRegistryMock;

    function setUp() public {
        vm.clearMockedCalls();
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        staderTreasury = vm.addr(105);
        staderToken = new StaderTokenMock();
        weth = new WETHMock();
        staderOracle = new StaderOracleMock();

        sdCollateralMock = vm.addr(106);
        mockSDCollateral(sdCollateralMock);

        permissionlessNodeRegistryMock = vm.addr(107);
        mockPermissionlessNodeRegistry(permissionlessNodeRegistryMock);

        address ethDepositAddr = vm.addr(102);
        address operator = address(500);

        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        poolUtils = new PoolUtilsMock(address(staderConfig), operator);

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updateSDCollateral(sdCollateralMock);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updatePermissionlessNodeRegistry(permissionlessNodeRegistryMock);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(staderTreasury);

        SDUtilityPool sdUtilityPoolImpl = new SDUtilityPool();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(sdUtilityPoolImpl),
            address(admin),
            ""
        );
        sdUtilityPool = SDUtilityPool(address(proxy));
        staderToken.approve(address(sdUtilityPool), 1000 ether);
        sdUtilityPool.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        SDIncentiveController sdIncentiveControllerImpl = new SDIncentiveController();
        TransparentUpgradeableProxy sdIncentiveControllerProxy = new TransparentUpgradeableProxy(
            address(sdIncentiveControllerImpl),
            address(admin),
            ""
        );
        sdIncentiveController = SDIncentiveController(address(sdIncentiveControllerProxy));
        sdIncentiveController.initialize(staderAdmin, address(staderConfig));

        OperatorRewardsCollector operatorRewardsCollectorImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRewardsCollectorProxy = new TransparentUpgradeableProxy(
            address(operatorRewardsCollectorImpl),
            address(admin),
            ""
        );
        operatorRewardsCollector = OperatorRewardsCollector(address(operatorRewardsCollectorProxy));
        operatorRewardsCollector.initialize(staderAdmin, address(staderConfig));
        staderConfig.updateSDIncentiveController(address(sdIncentiveController));
        staderConfig.updateSDUtilityPool(address(sdUtilityPool));
        staderConfig.updateStaderOracle(address(staderOracle));
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
            ""
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
        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        vm.expectEmit(true, true, true, true, address(operatorRewardsCollector));
        emit DepositedFor(address(this), staderManager, 0 ether);
        operatorRewardsCollector.depositFor{ value: 0 ether }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
    }

    function test_Claim(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getSDPriceInETH.selector),
            abi.encode(1e14)
        );
        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0);
        vm.stopPrank();
    }

    function test_Claim_PermissionedPoolOperator(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getSDPriceInETH.selector),
            abi.encode(1e14)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getOperatorPoolId.selector, staderManager),
            abi.encode(uint8(2)) // Assuming `POOL_ID()` for PermissionedNodeRegistry is `2`
        );

        vm.mockCall(
            address(permissionlessNodeRegistryMock),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(uint8(1))
        );

        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();

        assertEq(operatorRewardsCollector.balances(staderManager), 0);
        vm.stopPrank();
    }

    function test_ClaimWithAmount_PermissionlessNodeRegistry(uint256 amount, uint256 claimAmount) public {
        // Assume reasonable values for deposits and claims
        vm.assume(amount > 0 && amount < 100000 ether);

        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        // Mock the operator's pool ID to match the PermissionlessPool
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getOperatorPoolId.selector, staderManager),
            abi.encode(uint8(1))
        );

        vm.mockCall(
            address(permissionlessNodeRegistryMock),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(uint8(1))
        );
        uint256 withdrawableAmount = amount / 2;
        vm.startPrank(staderManager);

        if (!(claimAmount > withdrawableAmount || claimAmount > amount)) {
            // Case: Claiming valid amount
            operatorRewardsCollector.claimWithAmount(claimAmount);
            assertEq(operatorRewardsCollector.balances(staderManager), amount - claimAmount);
        }

        vm.stopPrank();
    }

    function test_ClaimWithAmount_PermissionedNodeRegistry(uint256 amount, uint256 claimAmount) public {
        // Assume reasonable values for deposits and claims
        vm.assume(amount > 0 && amount < 100000 ether);

        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        // Mock the operator's pool ID to match the PermissionedPool
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getOperatorPoolId.selector, staderManager),
            abi.encode(uint8(2))
        );

        vm.mockCall(
            address(permissionlessNodeRegistryMock),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(uint8(1))
        );

        vm.startPrank(staderManager);

        if (claimAmount > amount) {
            // Case: Attempting to claim more than balance, expect revert
            vm.expectRevert(InsufficientBalance.selector);
            operatorRewardsCollector.claimWithAmount(claimAmount);
        } else {
            // Case: Claiming valid amount
            operatorRewardsCollector.claimWithAmount(claimAmount);
            assertEq(operatorRewardsCollector.balances(staderManager), amount - claimAmount);
        }

        vm.stopPrank();
    }

    function test_claimLiquidationZeroAmount(uint256 amount) public {
        vm.assume(amount < 100000 ether);

        operatorRewardsCollector.depositFor{ value: amount }(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);

        operatorRewardsCollector.claimLiquidation(staderManager);
        assertEq(operatorRewardsCollector.balances(staderManager), amount);
    }

    function test_claimLiquidation() public {
        uint256 utilizeAmount = 1e22;

        address operator = vm.addr(110);
        address liquidator = vm.addr(109);

        operatorRewardsCollector.depositFor{ value: 100 ether }(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.mockCall(
            sdCollateralMock,
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );

        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getSDPriceInETH.selector),
            abi.encode(1e14)
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

    function test_claimLiquidationLastValidator() public {
        uint256 utilizeAmount = 1e4 ether;

        address operator = address(2);
        address liquidator = vm.addr(109);

        operatorRewardsCollector.depositFor{ value: 100 ether }(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.mockCall(
            sdCollateralMock,
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );
        vm.mockCall(
            sdCollateralMock,
            abi.encodeWithSelector(ISDCollateral.getOperatorInfo.selector),
            abi.encode(0, 0, 0)
        );
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getSDPriceInETH.selector),
            abi.encode(1e14)
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

        userData = sdUtilityPool.getUserData(operator);
        vm.startPrank(operator);
        vm.expectEmit();
        emit Claimed(operator, userData.totalCollateralInEth);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator), 0);
        vm.stopPrank();
    }

    function test_claimAfterLiquidation() public {
        uint256 utilizeAmount = 1e22;

        address operator = address(2);
        address liquidator = vm.addr(109);

        operatorRewardsCollector.depositFor{ value: 100 ether }(operator);
        assertEq(operatorRewardsCollector.balances(operator), 100 ether);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.mockCall(
            sdCollateralMock,
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getSDPriceInETH.selector),
            abi.encode(1e14)
        );

        vm.roll(block.number + 1900000000);

        UserData memory userData = sdUtilityPool.getUserData(operator);
        staderToken.transfer(liquidator, userData.totalInterestSD);
        vm.startPrank(liquidator);
        staderToken.approve(address(sdUtilityPool), userData.totalInterestSD);
        assertEq(operatorRewardsCollector.withdrawableInEth(operator), 0);
        sdUtilityPool.liquidationCall(operator);
        vm.stopPrank();

        vm.startPrank(operator);
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
        operatorRewardsCollector.depositFor{ value: depositAmount }(staderManager);

        // Simulate some earnings
        vm.roll(block.number + 100);

        vm.startPrank(staderManager);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(staderManager), 0 ether, "Balance should be zero after claim");
        vm.stopPrank();
    }

    function test_MultipleOperatorsDepositAndClaim() public {
        address operator1 = vm.addr(107);
        address operator2 = vm.addr(108);
        uint256 depositAmount1 = 30 ether;
        uint256 depositAmount2 = 40 ether;

        operatorRewardsCollector.depositFor{ value: depositAmount1 }(operator1);
        operatorRewardsCollector.depositFor{ value: depositAmount2 }(operator2);

        vm.startPrank(operator1);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator1), 0 ether, "Operator1 balance should be zero after claim");
        vm.stopPrank();

        vm.startPrank(operator2);
        operatorRewardsCollector.claim();
        assertEq(operatorRewardsCollector.balances(operator2), 0 ether, "Operator2 balance should be zero after claim");
        vm.stopPrank();
    }

    function test_UpdateWETHAddress() public {
        address newWethAddress = vm.addr(109);

        vm.startPrank(staderAdmin);
        operatorRewardsCollector.updateWethAddress(newWethAddress);
        assertEq(address(operatorRewardsCollector.weth()), newWethAddress, "WETH address should be updated");
        vm.stopPrank();

        // Test for unauthorized access
        address unauthorizedUser = vm.addr(110);
        address newWethAddress2 = vm.addr(111);
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            "AccessControl: account 0xb961768b578514debf079017ff78c47b0a6adbf6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        operatorRewardsCollector.updateWethAddress(newWethAddress2);
        vm.stopPrank();

        assertNotEq(address(operatorRewardsCollector.weth()), newWethAddress2, "WETH address should not be updated");
    }

    function test_MultipleDepositsAndTotalBalance(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 < 1000e18 && amount2 < 1000e18);

        operatorRewardsCollector.depositFor{ value: amount1 }(staderManager);
        operatorRewardsCollector.depositFor{ value: amount2 }(staderManager);
        assertEq(
            operatorRewardsCollector.balances(staderManager),
            amount1 + amount2,
            "Total balance should be the sum of all deposits"
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

    function mockSDCollateral(address _sdCollateralMock) private {
        emit log_named_address("sdCollateralMock", _sdCollateralMock);
        SDCollateralMock sdCollateralMockImpl = new SDCollateralMock();
        bytes memory mockCode = address(sdCollateralMockImpl).code;
        vm.etch(_sdCollateralMock, mockCode);
    }

    function mockPermissionlessNodeRegistry(address _permissionlessNodeRegistry) private {
        emit log_named_address("permissionlessNodeRegistry", _permissionlessNodeRegistry);
        PermissionlessNodeRegistryMock nodeRegistryMock = new PermissionlessNodeRegistryMock();
        bytes memory mockCode = address(nodeRegistryMock).code;
        vm.etch(_permissionlessNodeRegistry, mockCode);
    }
}
