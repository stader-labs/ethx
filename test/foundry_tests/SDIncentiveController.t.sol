// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/SDUtilityPool.sol';
import '../../contracts/SDIncentiveController.sol';

import '../mocks/SDCollateralMock.sol';
import '../mocks/StaderTokenMock.sol';
import '../mocks/SDIncentiveControllerMock.sol';
import '../mocks/OperatorRewardsCollectorMock.sol';
import '../mocks/PoolUtilsMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract SDIncentiveControllerTest is Test {
    event EmissionRateUpdated(uint256 newEmissionRate);
    event RewardEndBlockUpdated(uint256 newRewardEndBlock);
    event UpdatedStaderConfig(address staderConfig);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardUpdated(address indexed user, uint256 reward);

    address staderAdmin;
    address staderManager;
    address staderTreasury;

    StaderConfig staderConfig;
    SDUtilityPool sdUtilityPool;
    SDIncentiveController sdIncentiveController;
    StaderTokenMock staderToken;
    SDCollateralMock sdCollateral;
    OperatorRewardsCollectorMock operatorRewardsCollector;
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
        operatorRewardsCollector = new OperatorRewardsCollectorMock();
        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateOperatorRewardsCollector(address(operatorRewardsCollector));
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
        staderToken.approve(address(sdUtilityPool), 1 ether);
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

        vm.startPrank(staderAdmin);
        staderConfig.updateSDIncentiveController(address(sdIncentiveController));
        staderConfig.updateSDUtilityPool(address(sdUtilityPool));
        vm.stopPrank();
    }

    function test_Initialize() public {
        ProxyAdmin admin = new ProxyAdmin();
        SDIncentiveController sdIncentiveControllerImpl = new SDIncentiveController();
        TransparentUpgradeableProxy sdIncentiveControllerProxy = new TransparentUpgradeableProxy(
            address(sdIncentiveControllerImpl),
            address(admin),
            ''
        );
        SDIncentiveController sdIncentiveController2 = SDIncentiveController(address(sdIncentiveControllerProxy));

        vm.expectEmit();
        emit UpdatedStaderConfig(address(staderConfig));
        sdIncentiveController2.initialize(staderAdmin, address(staderConfig));
    }

    function test_VerifyInitialize() public {
        assertEq(address(sdIncentiveController.staderConfig()), address(staderConfig));
        assertEq(sdIncentiveController.emissionPerBlock(), 0);
        assertEq(sdIncentiveController.rewardEndBlock(), 0);
        assertEq(sdIncentiveController.lastUpdateBlockNumber(), 0);
        assertEq(sdIncentiveController.rewardPerTokenStored(), 0);
        assertEq(sdIncentiveController.DECIMAL(), 1e18);
        assertTrue(sdIncentiveController.hasRole(sdIncentiveController.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_SimpleIncentive(
        uint128 sdAmount,
        uint16 randomSeed,
        uint256 incentiveAmount,
        uint256 duration
    ) public {
        vm.assume(randomSeed > 1);

        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance / 4 && sdAmount > 1000e18);

        address user = vm.addr(randomSeed);
        address user2 = vm.addr(randomSeed - 1);

        staderToken.transfer(user, sdAmount);
        staderToken.transfer(user2, sdAmount);

        assertEq(sdIncentiveController.earned(user), 0);
        assertEq(sdIncentiveController.earned(user2), 0);

        delegateAndValidate(user2, sdAmount);

        vm.roll(block.number + 10);

        assertEq(sdIncentiveController.earned(user2), 0);

        (incentiveAmount, duration) = setupAndStartIncentive(incentiveAmount, duration);
        assertEq(sdIncentiveController.earned(user2), 0);

        vm.expectRevert(ISDIncentiveController.ExistingRewardPeriod.selector);
        vm.startPrank(staderManager);
        sdIncentiveController.start(incentiveAmount, duration);
        vm.stopPrank();

        vm.roll(block.number + 10);

        assertApproxEqAbs(
            sdIncentiveController.earned(address(this)) + sdIncentiveController.earned(user2),
            (incentiveAmount / duration) * 10,
            1e9
        );

        delegateAndValidate(user, sdAmount);

        vm.roll(block.number + 30);

        vm.startPrank(user2);
        sdUtilityPool.requestWithdrawWithSDAmount(sdAmount / 2);
        vm.stopPrank();

        vm.startPrank(staderAdmin);
        sdUtilityPool.updateMinBlockDelayToFinalizeRequest(0);
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 earned = sdIncentiveController.earned(user2);
        sdUtilityPool.claim(1);
        assertEq(staderToken.balanceOf(user2), earned + sdAmount / 2);
        vm.stopPrank();

        vm.roll(block.number + duration);
        uint256 preEarned = earned +
            sdIncentiveController.earned(user2) +
            sdIncentiveController.earned(user) +
            sdIncentiveController.earned(address(this));
        assertApproxEqAbs(preEarned, incentiveAmount, 1e9);

        vm.roll(block.number + duration * 10);
        assertEq(
            earned +
                sdIncentiveController.earned(user2) +
                sdIncentiveController.earned(user) +
                sdIncentiveController.earned(address(this)),
            preEarned
        );
    }

    function test_NoIncentive(uint128 sdAmount, uint16 randomSeed) public {
        vm.assume(randomSeed > 1);

        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance / 4 && sdAmount > 1000e18);

        address user = vm.addr(randomSeed);
        address user2 = vm.addr(randomSeed - 1);

        staderToken.transfer(user, sdAmount);
        staderToken.transfer(user2, sdAmount);

        assertEq(sdIncentiveController.earned(user), 0);
        assertEq(sdIncentiveController.earned(user2), 0);

        delegateAndValidate(user2, sdAmount);

        vm.roll(block.number + 10);

        assertEq(sdIncentiveController.earned(user2), 0);

        delegateAndValidate(user, sdAmount);
        vm.roll(block.number + 20);

        vm.startPrank(user2);
        sdUtilityPool.requestWithdrawWithSDAmount(sdAmount / 2);
        vm.stopPrank();

        vm.startPrank(staderAdmin);
        sdUtilityPool.updateMinBlockDelayToFinalizeRequest(0);
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 earned = sdIncentiveController.earned(user2);
        sdUtilityPool.claim(1);
        assertEq(staderToken.balanceOf(user2), sdAmount / 2);
        vm.stopPrank();

        vm.roll(block.number + 1000);
        uint256 preEarned = earned + sdIncentiveController.earned(user2) + sdIncentiveController.earned(user);
        assertEq(preEarned, 0);

        vm.roll(block.number + 10000);
        assertEq(earned + sdIncentiveController.earned(user2) + sdIncentiveController.earned(user), preEarned);
    }

    function testWithdrawMultiples(
        uint256 utilizeAmount,
        uint256 incentiveAmount,
        uint256 duration
    ) public {
        vm.assume(utilizeAmount > 1e20 && utilizeAmount < 1e25);

        address user1 = address(1);
        address user2 = address(2);

        (incentiveAmount, duration) = setupAndStartIncentive(incentiveAmount, duration);

        staderToken.transfer(user1, utilizeAmount);
        staderToken.transfer(user2, utilizeAmount);

        delegateAndValidate(user1, utilizeAmount / 10);
        delegateAndValidate(user2, utilizeAmount);

        vm.roll(block.number + duration);
        uint256 earn1 = sdIncentiveController.earned(user1);
        uint256 earn2 = sdIncentiveController.earned(user2);

        uint256 user1PrevBalance = staderToken.balanceOf(user1);
        uint256 user2PrevBalance = staderToken.balanceOf(user2);

        vm.startPrank(user1);
        sdUtilityPool.requestWithdrawWithSDAmount(utilizeAmount / 10);
        vm.stopPrank();

        vm.startPrank(user2);
        sdUtilityPool.requestWithdrawWithSDAmount(utilizeAmount);
        vm.stopPrank();

        vm.startPrank(staderAdmin);
        sdUtilityPool.updateMinBlockDelayToFinalizeRequest(0);
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true, address(sdIncentiveController));
        emit RewardClaimed(user1, earn1);
        sdUtilityPool.claim(1);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectEmit(true, true, true, true, address(sdIncentiveController));
        emit RewardClaimed(user2, earn2);
        sdUtilityPool.claim(2);
        vm.stopPrank();

        assertTrue(earn1 > 0, 'User1 did not earn any rewards');
        assertTrue(earn2 > 0, 'User2 did not earn any rewards');

        uint256 user1FinalGain = staderToken.balanceOf(user1) - user1PrevBalance;
        uint256 user2FinalGain = staderToken.balanceOf(user2) - user2PrevBalance;

        console.log(address(this));
        assertApproxEqAbs(user2FinalGain / 10, user1FinalGain, 10);
    }

    function test_UpdateStaderConfig(uint16 randomSeed) public {
        vm.assume(randomSeed > 0);
        address inputAddr = vm.addr(randomSeed);
        vm.expectRevert();
        sdIncentiveController.updateStaderConfig(inputAddr);
        vm.startPrank(staderAdmin);
        vm.expectRevert(UtilLib.ZeroAddress.selector);
        sdIncentiveController.updateStaderConfig(address(0));
        sdIncentiveController.updateStaderConfig(inputAddr);
        assertEq(address(sdIncentiveController.staderConfig()), inputAddr);
    }

    function test_startIncentive(uint256 incentiveAmount, uint256 duration) public {
        vm.assume(incentiveAmount > 0);
        vm.assume(duration > 0);

        incentiveAmount = ((incentiveAmount % 10) + 2) * 1e18;
        duration = ((duration % 10) + 1) * 100;
        incentiveAmount = (incentiveAmount / duration) * duration;
        staderToken.transfer(staderManager, incentiveAmount);

        staderToken.approve(address(sdIncentiveController), incentiveAmount);
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdIncentiveController.start(incentiveAmount, duration);

        // 0 rewards
        vm.startPrank(staderManager);
        vm.expectRevert(ISDIncentiveController.InvalidRewardAmount.selector);
        sdIncentiveController.start(0, duration);
        vm.stopPrank();

        // 0 duration
        vm.startPrank(staderManager);
        staderToken.approve(address(sdIncentiveController), incentiveAmount);
        vm.expectRevert(ISDIncentiveController.InvalidEndBlock.selector);
        sdIncentiveController.start(incentiveAmount, 0);
        vm.stopPrank();

        // Undivisible reward and duration
        vm.startPrank(staderManager);
        staderToken.approve(address(sdIncentiveController), 123456);
        vm.expectRevert(ISDIncentiveController.InvalidRewardAmount.selector);
        sdIncentiveController.start(123456, 10);
        vm.stopPrank();

        // No approval
        vm.startPrank(staderManager);
        vm.expectRevert('ERC20: insufficient allowance');
        sdIncentiveController.start(1e22, 10);
        vm.stopPrank();

        // Less than DECIMAL
        vm.startPrank(staderManager);
        vm.expectRevert(ISDIncentiveController.InvalidRewardAmount.selector);
        sdIncentiveController.start(1e17, 10);
        vm.stopPrank();

        vm.startPrank(staderManager);
        staderToken.approve(address(sdIncentiveController), incentiveAmount);
        vm.expectEmit(true, true, true, true, address(sdIncentiveController));
        emit EmissionRateUpdated(incentiveAmount / duration);
        emit RewardEndBlockUpdated(block.number + duration);
        sdIncentiveController.start(incentiveAmount, duration);
        vm.stopPrank();
    }

    function setupAndStartIncentive(uint256 incentiveAmount, uint256 duration) internal returns (uint256, uint256) {
        vm.assume(incentiveAmount > 0 && duration > 0);
        incentiveAmount = adjustIncentiveAmount(incentiveAmount);
        duration = adjustDuration(duration);
        incentiveAmount = (incentiveAmount / duration) * duration;
        staderToken.transfer(staderManager, incentiveAmount);

        console.log('Incentive amount: ', incentiveAmount);
        console.log('Duration: ', duration);

        vm.startPrank(staderManager);
        staderToken.approve(address(sdIncentiveController), incentiveAmount);
        sdIncentiveController.start(incentiveAmount, duration);
        vm.stopPrank();

        return (incentiveAmount, duration);
    }

    function adjustIncentiveAmount(uint256 amount) internal pure returns (uint256) {
        return ((amount % 10) + 2) * 1e18;
    }

    function adjustDuration(uint256 duration) internal pure returns (uint256) {
        return ((duration % 10) + 1) * 100;
    }

    function delegateAndValidate(address user, uint256 sdAmount) internal {
        vm.startPrank(user);
        staderToken.approve(address(sdUtilityPool), sdAmount);
        vm.expectEmit(true, true, true, true, address(sdIncentiveController));
        emit RewardUpdated(user, 0);
        sdUtilityPool.delegate(sdAmount);
        vm.stopPrank();
        assertEq(sdIncentiveController.earned(user), 0);
    }
}
