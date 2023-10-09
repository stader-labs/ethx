// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/ETHx.sol';
import '../../contracts/StaderConfig.sol';
import '../../contracts/UserWithdrawalManager.sol';

import '../mocks/StaderOracleMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract UserWithdrawalManagerTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;

    ETHx ethX;
    StaderConfig staderConfig;
    UserWithdrawalManager userWithdrawalManager;

    StaderOracleMock staderOracle;
    StakePoolManagerMock staderStakePoolManager;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        address ethDepositAddr = vm.addr(103);
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
        UserWithdrawalManager userWithdrawalManagerImp = new UserWithdrawalManager();
        TransparentUpgradeableProxy userWithdrawalManagerProxy = new TransparentUpgradeableProxy(
            address(userWithdrawalManagerImp),
            address(admin),
            ''
        );

        userWithdrawalManager = UserWithdrawalManager(payable(userWithdrawalManagerProxy));
        userWithdrawalManager.initialize(staderAdmin, address(staderConfig));

        staderOracle = new StaderOracleMock();
        staderStakePoolManager = new StakePoolManagerMock();

        vm.startPrank(staderAdmin);
        staderConfig.updateETHxToken(address(ethX));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updateStakePoolManager(address(staderStakePoolManager));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        ethX.grantRole(ethX.MINTER_ROLE(), address(staderStakePoolManager));
        ethX.grantRole(ethX.BURNER_ROLE(), address(userWithdrawalManager));

        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        UserWithdrawalManager userWithdrawalManagerImp = new UserWithdrawalManager();
        TransparentUpgradeableProxy userWithdrawalManagerProxy = new TransparentUpgradeableProxy(
            address(userWithdrawalManagerImp),
            address(admin),
            ''
        );

        userWithdrawalManager = UserWithdrawalManager(payable(userWithdrawalManagerProxy));
        userWithdrawalManager.initialize(staderAdmin, address(staderConfig));
    }

    function test_UserWithdrawalManagerInitialize() public {
        assertEq(address(userWithdrawalManager.staderConfig()), address(staderConfig));
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 1);
        assertEq(userWithdrawalManager.nextRequestId(), 1);
        assertEq(userWithdrawalManager.ethRequestedForWithdraw(), 0);
        assertEq(userWithdrawalManager.finalizationBatchLimit(), 50);
        assertEq(userWithdrawalManager.maxNonRedeemedUserRequestCount(), 1000);
        assertTrue(userWithdrawalManager.hasRole(userWithdrawalManager.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_ReceiveFunction() public {
        vm.deal(address(this), 2 ether);
        payable(userWithdrawalManager).call{value: 1 ether}('');
        assertEq(address(this).balance, 1 ether);
        assertEq(address(userWithdrawalManager).balance, 1 ether);
    }

    function test_updateFinalizationBatchLimit(uint64 _finalizationBatchLimit) public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        userWithdrawalManager.updateFinalizationBatchLimit(_finalizationBatchLimit);
        vm.prank(staderManager);
        userWithdrawalManager.updateFinalizationBatchLimit(_finalizationBatchLimit);
        assertEq(userWithdrawalManager.finalizationBatchLimit(), _finalizationBatchLimit);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        userWithdrawalManager.updateStaderConfig(newStaderConfig);
        assertEq(address(userWithdrawalManager.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        userWithdrawalManager.updateStaderConfig(newStaderConfig);
        assertEq(address(userWithdrawalManager.staderConfig()), newStaderConfig);
    }

    function test_requestWithdraw(uint64 randomPrivateKey, uint64 randomPrivateKey2) public {
        vm.assume(
            randomPrivateKey > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        vm.assume(
            randomPrivateKey2 > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        address ethXHolder = vm.addr(randomPrivateKey);
        address owner = vm.addr(randomPrivateKey2);
        vm.prank(staderManager);
        userWithdrawalManager.pause();
        vm.expectRevert();
        userWithdrawalManager.requestWithdraw(1000, owner);
        vm.prank(staderAdmin);
        userWithdrawalManager.unpause();
        vm.expectRevert(IUserWithdrawalManager.ZeroAddressReceived.selector);
        userWithdrawalManager.requestWithdraw(1000, address(0));

        vm.expectRevert(IUserWithdrawalManager.InvalidWithdrawAmount.selector);
        userWithdrawalManager.requestWithdraw(1000, owner);
        vm.expectRevert(IUserWithdrawalManager.InvalidWithdrawAmount.selector);
        userWithdrawalManager.requestWithdraw(100000 ether, owner);

        vm.prank(address(staderStakePoolManager));
        ethX.mint(ethXHolder, 100 ether);
        assertEq(ethX.balanceOf(ethXHolder), 100 ether);
        vm.startPrank(ethXHolder);
        ethX.approve(address(userWithdrawalManager), type(uint256).max);
        userWithdrawalManager.requestWithdraw(10 ether, owner);
        assertEq(userWithdrawalManager.nextRequestId(), 2);
        assertEq(ethX.balanceOf(ethXHolder), 90 ether);
        assertEq(userWithdrawalManager.ethRequestedForWithdraw(), 10 ether);

        vm.expectRevert();
        userWithdrawalManager.requestWithdraw(100 ether, owner);
    }

    function test_finalizeUserWithdrawalRequest(uint64 randomPrivateKey, uint64 randomPrivateKey2) public {
        vm.assume(randomPrivateKey != randomPrivateKey2);
        vm.assume(
            randomPrivateKey > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        vm.assume(
            randomPrivateKey2 > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        address ethXHolder = vm.addr(randomPrivateKey);
        address owner = vm.addr(randomPrivateKey2);

        vm.prank(staderManager);
        userWithdrawalManager.pause();
        vm.expectRevert();
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        vm.prank(staderAdmin);
        userWithdrawalManager.unpause();
        vm.mockCall(address(staderOracle), abi.encodeWithSelector(IStaderOracle.safeMode.selector), abi.encode(true));
        vm.mockCall(
            address(staderStakePoolManager),
            abi.encodeWithSelector(IStaderStakePoolManager.isVaultHealthy.selector),
            abi.encode(false)
        );

        vm.expectRevert(IUserWithdrawalManager.UnsupportedOperationInSafeMode.selector);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        vm.mockCall(address(staderOracle), abi.encodeWithSelector(IStaderOracle.safeMode.selector), abi.encode(false));
        vm.expectRevert(IUserWithdrawalManager.ProtocolNotHealthy.selector);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        vm.mockCall(
            address(staderStakePoolManager),
            abi.encodeWithSelector(IStaderStakePoolManager.isVaultHealthy.selector),
            abi.encode(true)
        );
        vm.prank(address(staderStakePoolManager));
        ethX.mint(ethXHolder, 100 ether);
        assertEq(ethX.balanceOf(ethXHolder), 100 ether);
        vm.startPrank(ethXHolder);
        ethX.approve(address(userWithdrawalManager), type(uint256).max);
        userWithdrawalManager.requestWithdraw(10 ether, owner);
        userWithdrawalManager.requestWithdraw(10 ether, owner);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);
        assertEq(userWithdrawalManager.getRequestIdsByUser(owner).length, 2);
        assertEq(userWithdrawalManager.getRequestIdsByUser(ethXHolder).length, 3);
        assertEq(userWithdrawalManager.ethRequestedForWithdraw(), 50 ether);
        assertEq(ethX.balanceOf(ethXHolder), 50 ether);
        assertEq(address(userWithdrawalManager).balance, 0);
        assertEq(ethX.balanceOf(address(userWithdrawalManager)), 50 ether);

        assertEq(userWithdrawalManager.nextRequestId(), 6);
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 1);

        userWithdrawalManager.finalizeUserWithdrawalRequest();
        assertEq(ethX.balanceOf(address(userWithdrawalManager)), 50 ether);
        assertEq(address(userWithdrawalManager).balance, 0);
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 1);

        vm.deal(address(staderStakePoolManager), 24 ether);
        vm.roll(block.number + 599);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        assertEq(ethX.balanceOf(address(userWithdrawalManager)), 50 ether);
        assertEq(address(userWithdrawalManager).balance, 0);
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 1);

        vm.roll(block.number + 600);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        assertEq(ethX.balanceOf(address(userWithdrawalManager)), 20 ether);
        assertEq(address(userWithdrawalManager).balance, 24 ether);
        assertEq(userWithdrawalManager.ethRequestedForWithdraw(), 20 ether);
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 4);

        vm.deal(address(staderStakePoolManager), 50 ether);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        assertEq(ethX.balanceOf(address(userWithdrawalManager)), 0);
        assertEq(userWithdrawalManager.ethRequestedForWithdraw(), 0);
        assertEq(address(userWithdrawalManager).balance, 40 ether);
        assertEq(userWithdrawalManager.nextRequestIdToFinalize(), 6);
    }

    function test_claim(uint64 randomPrivateKey, uint64 randomPrivateKey2) public {
        vm.mockCall(address(staderOracle), abi.encodeWithSelector(IStaderOracle.safeMode.selector), abi.encode(false));
        vm.mockCall(
            address(staderStakePoolManager),
            abi.encodeWithSelector(IStaderStakePoolManager.isVaultHealthy.selector),
            abi.encode(true)
        );
        vm.assume(randomPrivateKey != randomPrivateKey2);
        vm.assume(
            randomPrivateKey > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        vm.assume(
            randomPrivateKey2 > 0 &&
                vm.addr(randomPrivateKey) != address(userWithdrawalManager) &&
                vm.addr(randomPrivateKey) != address(staderStakePoolManager)
        );
        address ethXHolder = vm.addr(randomPrivateKey);
        address owner = vm.addr(randomPrivateKey2);
        vm.prank(address(staderStakePoolManager));
        ethX.mint(ethXHolder, 100 ether);
        vm.startPrank(ethXHolder);
        ethX.approve(address(userWithdrawalManager), type(uint256).max);
        userWithdrawalManager.requestWithdraw(10 ether, owner);
        userWithdrawalManager.requestWithdraw(10 ether, owner);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);
        userWithdrawalManager.requestWithdraw(10 ether, ethXHolder);

        vm.roll(block.number + 600);
        vm.deal(address(staderStakePoolManager), 100 ether);
        userWithdrawalManager.finalizeUserWithdrawalRequest();
        vm.stopPrank();
        vm.startPrank(owner);
        vm.expectRevert();
        userWithdrawalManager.claim(6);

        vm.expectRevert(IUserWithdrawalManager.CallerNotAuthorizedToRedeem.selector);
        userWithdrawalManager.claim(3);

        assertEq(userWithdrawalManager.getRequestIdsByUser(owner).length, 2);
        assertEq(userWithdrawalManager.getRequestIdsByUser(ethXHolder).length, 3);
        assertEq(address(userWithdrawalManager).balance, 40 ether);
        userWithdrawalManager.claim(1);
        assertEq(address(userWithdrawalManager).balance, 32 ether);
        assertEq(address(owner).balance, 8 ether);
        assertEq(userWithdrawalManager.getRequestIdsByUser(owner).length, 1);

        vm.startPrank(ethXHolder);
        userWithdrawalManager.claim(3);
        userWithdrawalManager.claim(4);
        assertEq(userWithdrawalManager.getRequestIdsByUser(ethXHolder).length, 1);
        assertEq(address(userWithdrawalManager).balance, 16 ether);
        assertEq(address(ethXHolder).balance, 16 ether);
    }
}
