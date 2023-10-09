// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/ETHx.sol';
import '../../contracts/StaderConfig.sol';
import '../../contracts/StaderStakePoolsManager.sol';

import '../mocks/PoolMock.sol';
import '../mocks/PoolUtilsMock.sol';
import '../mocks/StaderOracleMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderStakePoolManagerTest is Test {
    using Math for uint256;
    address staderAdmin;
    address staderManager;
    address operator;

    ETHx ethX;
    StaderConfig staderConfig;
    StaderStakePoolsManager stakePoolManager;

    PoolMock permissionlessPoolAddress;
    PoolMock permissionedPoolAddress;
    PoolUtilsMock poolUtils;
    StaderOracleMock staderOracle;

    address poolSelector;
    address userWithdrawManager;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        address ethDepositAddr = vm.addr(103);
        userWithdrawManager = vm.addr(104);
        poolSelector = vm.addr(105);
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, address(ethDepositAddr));

        ETHx ethXImpl = new ETHx();
        TransparentUpgradeableProxy ethXProxy = new TransparentUpgradeableProxy(address(ethXImpl), address(admin), '');
        ethX = ETHx(address(ethXProxy));
        ethX.initialize(staderAdmin, address(staderConfig));

        StaderStakePoolsManager staderStakePoolManagerImpl = new StaderStakePoolsManager();
        TransparentUpgradeableProxy staderStakePoolManagerProxy = new TransparentUpgradeableProxy(
            address(staderStakePoolManagerImpl),
            address(admin),
            ''
        );

        stakePoolManager = StaderStakePoolsManager(payable(staderStakePoolManagerProxy));
        stakePoolManager.initialize(staderAdmin, address(staderConfig));

        permissionlessPoolAddress = new PoolMock(vm.addr(120));
        permissionedPoolAddress = new PoolMock(vm.addr(130));
        staderOracle = new StaderOracleMock();
        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateETHxToken(address(ethX));
        staderConfig.updatePoolSelector(poolSelector);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updatePermissionlessPool(address(permissionlessPoolAddress));
        staderConfig.updatePermissionedPool(address(permissionedPoolAddress));
        staderConfig.updateUserWithdrawManager(userWithdrawManager);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        ethX.grantRole(ethX.MINTER_ROLE(), address(stakePoolManager));
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        StaderStakePoolsManager staderStakePoolManagerImpl = new StaderStakePoolsManager();
        TransparentUpgradeableProxy staderStakePoolManagerProxy = new TransparentUpgradeableProxy(
            address(staderStakePoolManagerImpl),
            address(admin),
            ''
        );

        stakePoolManager = StaderStakePoolsManager(payable(staderStakePoolManagerProxy));
        stakePoolManager.initialize(staderAdmin, address(staderConfig));
    }

    function test_StaderStakePoolsManager() public {
        assertEq(address(stakePoolManager.staderConfig()), address(staderConfig));
        assertEq(stakePoolManager.lastExcessETHDepositBlock(), block.number);
        assertEq(stakePoolManager.excessETHDepositCoolDown(), 3 * 7200);
        assertTrue(stakePoolManager.hasRole(stakePoolManager.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_ReceiveFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderStakePoolManager.UnsupportedOperation.selector);
        payable(stakePoolManager).call{value: 1 ether}('');
        vm.stopPrank();
    }

    function test_FallbackFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderStakePoolManager.UnsupportedOperation.selector);
        payable(stakePoolManager).call{value: 1 ether}('abi.encodeWithSignature("nonExistentFunction()")');
        vm.stopPrank();
    }

    function test_receiveExecutionLayerRewards(uint64 privateKey, uint64 amount) public {
        vm.assume(privateKey > 0);
        address randomAddr = vm.addr(privateKey);
        startHoax(randomAddr, amount);
        assertEq(address(stakePoolManager).balance, 0);
        stakePoolManager.receiveExecutionLayerRewards{value: amount}();
        assertEq(address(stakePoolManager).balance, amount);
    }

    function test_receiveWithdrawVaultUserShare(uint64 privateKey, uint64 amount) public {
        vm.assume(privateKey > 0);
        address randomAddr = vm.addr(privateKey);
        startHoax(randomAddr, amount);
        assertEq(address(stakePoolManager).balance, 0);
        stakePoolManager.receiveWithdrawVaultUserShare{value: amount}();
        assertEq(address(stakePoolManager).balance, amount);
    }

    function test_receiveEthFromAuction(uint64 privateKey, uint64 amount) public {
        vm.assume(privateKey > 0);
        address randomAddr = vm.addr(privateKey);
        startHoax(randomAddr, amount);
        assertEq(address(stakePoolManager).balance, 0);
        stakePoolManager.receiveEthFromAuction{value: amount}();
        assertEq(address(stakePoolManager).balance, amount);
    }

    function test_receiveExcessEthFromPool(uint64 privateKey, uint64 amount) public {
        vm.assume(privateKey > 0);
        address randomAddr = vm.addr(privateKey);
        startHoax(randomAddr, amount);
        assertEq(address(stakePoolManager).balance, 0);
        stakePoolManager.receiveExcessEthFromPool{value: amount}(1);
        assertEq(address(stakePoolManager).balance, amount);
    }

    function test_transferETHToUserWithdrawManager(uint64 amount) public {
        vm.deal(address(stakePoolManager), amount);
        vm.prank(userWithdrawManager);
        stakePoolManager.transferETHToUserWithdrawManager(amount);
        assertEq(address(stakePoolManager).balance, 0);
        assertEq(userWithdrawManager.balance, amount);
    }

    function test_updateExcessETHDepositCoolDown(uint64 excessETHDepositCoolDown) public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        stakePoolManager.updateExcessETHDepositCoolDown(excessETHDepositCoolDown);
        vm.prank(staderManager);
        stakePoolManager.updateExcessETHDepositCoolDown(excessETHDepositCoolDown);
        assertEq(stakePoolManager.excessETHDepositCoolDown(), excessETHDepositCoolDown);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        vm.expectRevert(UtilLib.ZeroAddress.selector);
        stakePoolManager.updateStaderConfig(address(0));
        stakePoolManager.updateStaderConfig(newStaderConfig);
        assertEq(address(stakePoolManager.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        stakePoolManager.updateStaderConfig(newStaderConfig);
        assertEq(address(stakePoolManager.staderConfig()), newStaderConfig);
    }

    function test_getExchangeRate(uint256 _totalETHx, uint256 _totalETH) public {
        vm.assume(_totalETHx > 0 && _totalETHx < 120 * 10**24);
        vm.assume(_totalETH > 0 && _totalETH < 120 * 10**24);
        assertEq(stakePoolManager.getExchangeRate(), 1 * 10**18);
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, _totalETH, _totalETHx)
        );
        uint256 exchangeRate = (_totalETH * 10**18) / _totalETHx;
        assertEq(stakePoolManager.getExchangeRate(), exchangeRate);
    }

    function test_convertToShares() public {
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 0, 1 ether)
        );
        vm.expectRevert();
        stakePoolManager.convertToShares(1 ether);
        vm.expectRevert();
        stakePoolManager.previewDeposit(1 ether);
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 1 ether, 0)
        );
        assertEq(stakePoolManager.convertToShares(1 ether), 1 ether);
        assertEq(stakePoolManager.previewDeposit(1 ether), 1 ether);
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 1 ether, 1 ether)
        );
        assertEq(stakePoolManager.convertToShares(1 ether), 1 ether);
        assertEq(stakePoolManager.convertToShares(0), 0);
        assertEq(stakePoolManager.previewDeposit(1 ether), 1 ether);
        assertEq(stakePoolManager.previewDeposit(0), 0);
    }

    function test_convertToAssets() public {
        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 1 ether, 0)
        );
        assertEq(stakePoolManager.convertToAssets(1 ether), 1 ether);
        assertEq(stakePoolManager.convertToAssets(1000 ether), 1000 ether);

        assertEq(stakePoolManager.previewWithdraw(1 ether), 1 ether);
        assertEq(stakePoolManager.previewWithdraw(1000 ether), 1000 ether);

        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 1000 ether, 1 ether)
        );
        assertEq(stakePoolManager.convertToAssets(1 ether), 1000 ether);
        assertEq(stakePoolManager.previewWithdraw(1 ether), 1000 ether);

        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 1000 ether, 500 ether)
        );
        assertEq(stakePoolManager.convertToAssets(1 ether), 2 ether);
        assertEq(stakePoolManager.previewWithdraw(1 ether), 2 ether);

        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 0, 100 ether)
        );
        assertEq(stakePoolManager.convertToAssets(1 ether), 0);
        assertEq(stakePoolManager.convertToAssets(1000 ether), 0);
        assertEq(stakePoolManager.convertToAssets(0), 0);

        assertEq(stakePoolManager.previewWithdraw(1 ether), 0);
        assertEq(stakePoolManager.previewWithdraw(1000 ether), 0);
        assertEq(stakePoolManager.previewWithdraw(0), 0);
    }

    function test_deposit() public {
        address receiver = vm.addr(110);

        vm.prank(staderManager);
        stakePoolManager.pause();
        vm.expectRevert('Pausable: paused');
        stakePoolManager.deposit{value: 1}(receiver);
        vm.prank(staderAdmin);
        stakePoolManager.unpause();

        vm.expectRevert(IStaderStakePoolManager.InvalidDepositAmount.selector);
        stakePoolManager.deposit{value: 1}(receiver);

        vm.expectRevert(IStaderStakePoolManager.InvalidDepositAmount.selector);
        stakePoolManager.deposit{value: 100000 ether}(receiver);
        assertEq(stakePoolManager.deposit{value: 100 ether}(receiver), 100 ether);
        assertEq(ethX.balanceOf(receiver), 100 ether);
        assertEq(address(stakePoolManager).balance, 100 ether);
    }

    function test_MinMaxDeposit() public {
        assertEq(stakePoolManager.minDeposit(), 1e14);
        assertEq(stakePoolManager.maxDeposit(), 10000 ether);

        vm.mockCall(
            address(staderOracle),
            abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector),
            abi.encode(block.number, 0, 1 ether)
        );
        assertEq(stakePoolManager.minDeposit(), 0);
        assertEq(stakePoolManager.maxDeposit(), 0);
    }

    function test_validatorBatchDeposit() public {
        vm.prank(staderManager);
        stakePoolManager.pause();
        vm.expectRevert();
        stakePoolManager.validatorBatchDeposit(1);
        vm.prank(staderAdmin);
        stakePoolManager.unpause();

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.isExistingPoolId.selector),
            abi.encode(false)
        );
        vm.expectRevert(IStaderStakePoolManager.PoolIdDoesNotExit.selector);
        stakePoolManager.validatorBatchDeposit(1);
        stakePoolManager.deposit{value: 100 ether}(address(this));
        vm.mockCall(address(poolUtils), abi.encodeWithSelector(IPoolUtils.isExistingPoolId.selector), abi.encode(true));
        vm.mockCall(
            address(userWithdrawManager),
            abi.encodeWithSelector(IUserWithdrawalManager.ethRequestedForWithdraw.selector),
            abi.encode(80 ether)
        );
        vm.expectRevert(IStaderStakePoolManager.InsufficientBalance.selector);
        stakePoolManager.validatorBatchDeposit(1);

        vm.mockCall(
            address(userWithdrawManager),
            abi.encodeWithSelector(IUserWithdrawalManager.ethRequestedForWithdraw.selector),
            abi.encode(70 ether)
        );
        vm.expectRevert(IStaderStakePoolManager.InsufficientBalance.selector);
        stakePoolManager.validatorBatchDeposit(2);

        vm.mockCall(
            address(poolSelector),
            abi.encodeWithSelector(IPoolSelector.computePoolAllocationForDeposit.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(userWithdrawManager),
            abi.encodeWithSelector(IUserWithdrawalManager.ethRequestedForWithdraw.selector),
            abi.encode(0)
        );
        stakePoolManager.validatorBatchDeposit(2);
        assertEq(address(stakePoolManager).balance, 100 ether);
        vm.mockCall(
            address(poolSelector),
            abi.encodeWithSelector(IPoolSelector.computePoolAllocationForDeposit.selector),
            abi.encode(3)
        );

        stakePoolManager.validatorBatchDeposit(2);
        assertEq(address(stakePoolManager).balance, 4 ether);
        assertEq(address(permissionedPoolAddress).balance, 96 ether);
    }

    function test_depositETHOverTargetWeight() public {
        stakePoolManager.deposit{value: 100 ether}(address(this));
        vm.expectRevert(IStaderStakePoolManager.CooldownNotComplete.selector);
        stakePoolManager.depositETHOverTargetWeight();

        vm.mockCall(
            address(userWithdrawManager),
            abi.encodeWithSelector(IUserWithdrawalManager.ethRequestedForWithdraw.selector),
            abi.encode(70 ether)
        );
        vm.roll(block.number + stakePoolManager.excessETHDepositCoolDown());
        vm.expectRevert(IStaderStakePoolManager.InsufficientBalance.selector);
        stakePoolManager.depositETHOverTargetWeight();
        vm.mockCall(
            address(userWithdrawManager),
            abi.encodeWithSelector(IUserWithdrawalManager.ethRequestedForWithdraw.selector),
            abi.encode(0)
        );
        uint256[] memory selectedPoolCapacity = new uint256[](2);
        selectedPoolCapacity[0] = 2;
        selectedPoolCapacity[1] = 1;

        uint8[] memory poolIdArray = new uint8[](2);
        poolIdArray[0] = 1;
        poolIdArray[1] = 2;
        vm.mockCall(
            poolSelector,
            abi.encodeWithSelector(IPoolSelector.poolAllocationForExcessETHDeposit.selector),
            abi.encode(selectedPoolCapacity, poolIdArray)
        );
        stakePoolManager.depositETHOverTargetWeight();
        assertEq(address(stakePoolManager).balance, 12 ether);
        assertEq(address(permissionedPoolAddress).balance, 32 ether);
        assertEq(address(permissionlessPoolAddress).balance, 56 ether);
    }
}
