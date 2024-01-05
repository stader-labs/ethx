// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/SDUtilityPool.sol';

import '../mocks/SDCollateralMock.sol';
import '../mocks/StaderTokenMock.sol';
import '../mocks/SDIncentiveControllerMock.sol';
import '../mocks/OperatorRewardsCollectorMock.sol';
import '../mocks/PoolUtilsMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract SDUtilityPoolTest is Test {
    address staderAdmin;
    address staderManager;
    address staderTreasury;

    StaderConfig staderConfig;
    SDUtilityPool sdUtilityPool;
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
        SDIncentiveControllerMock sdIncentiveController = new SDIncentiveControllerMock();
        operatorRewardsCollector = new OperatorRewardsCollectorMock();
        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateOperatorRewardsCollector(address(operatorRewardsCollector));
        staderConfig.updateSDIncentiveController(address(sdIncentiveController));
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
        sdUtilityPool.initialize(staderAdmin, address(staderConfig));

        vm.prank(staderAdmin);
        sdUtilityPool.updateRiskConfig(70, 30, 5, 50);
    }

    function test_Initialize() public {
        ProxyAdmin admin = new ProxyAdmin();
        SDUtilityPool collateralImpl = new SDUtilityPool();
        TransparentUpgradeableProxy collateralProxy = new TransparentUpgradeableProxy(
            address(collateralImpl),
            address(admin),
            ''
        );
        SDUtilityPool sdCollateral2 = SDUtilityPool(address(collateralProxy));
        sdCollateral2.initialize(staderAdmin, address(staderConfig));
    }

    function test_VerifyInitialize() public {
        assertEq(address(sdUtilityPool.staderConfig()), address(staderConfig));
        assertEq(sdUtilityPool.utilizeIndex(), 1e18);
        assertEq(sdUtilityPool.utilizationRatePerBlock(), 38051750380);
        assertEq(sdUtilityPool.protocolFee(), 0);
        assertEq(sdUtilityPool.nextRequestId(), 1);
        assertEq(sdUtilityPool.nextRequestIdToFinalize(), 1);
        assertEq(sdUtilityPool.finalizationBatchLimit(), 50);
        assertEq(sdUtilityPool.accrualBlockNumber(), block.number);
        assertEq(sdUtilityPool.minBlockDelayToFinalizeRequest(), 50400);
        assertEq(sdUtilityPool.maxNonRedeemedDelegatorRequestCount(), 1000);
        assertEq(sdUtilityPool.maxETHWorthOfSDPerValidator(), 1 ether);
        assertEq(sdUtilityPool.conservativeEthPerKey(), 2 ether);
        assertTrue(sdUtilityPool.hasRole(sdUtilityPool.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_Delegate(
        uint128 sdAmount,
        uint128 approveAmount,
        uint16 randomSeed,
        uint16 randomSeed2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance / 4);

        vm.assume(randomSeed > 0);
        vm.assume(randomSeed2 > 0 && randomSeed != randomSeed2);
        address user = vm.addr(randomSeed);
        address user2 = vm.addr(randomSeed2);

        staderToken.transfer(user, sdAmount);
        staderToken.transfer(user2, sdAmount);
        vm.startPrank(user2); // makes user as the caller untill stopPrank();
        vm.assume(approveAmount >= sdAmount);
        staderToken.approve(address(sdUtilityPool), approveAmount);
        vm.prank(staderManager);
        sdUtilityPool.pause();
        vm.startPrank(user2);
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.delegate(sdAmount);
        vm.prank(staderAdmin);
        sdUtilityPool.unpause();
        vm.startPrank(user2);
        sdUtilityPool.delegate(sdAmount);
        vm.stopPrank();
        staderToken.transfer(address(sdUtilityPool), sdAmount);
        vm.startPrank(user); // makes user as the caller untill stopPrank();
        vm.assume(approveAmount >= sdAmount);
        staderToken.approve(address(sdUtilityPool), approveAmount);
        uint256 exchangeRate = sdUtilityPool.getLatestExchangeRate();
        sdUtilityPool.delegate(sdAmount);
        assertEq(sdUtilityPool.exchangeRateStored(), sdUtilityPool.exchangeRateCurrent());
        uint256 cTokenBalance = (1e18 * uint256(sdAmount)) / exchangeRate;
        assertEq(staderToken.balanceOf(address(sdUtilityPool)), 3 * sdAmount);

        assertEq(sdUtilityPool.delegatorCTokenBalance(user), cTokenBalance);
        assertEq(sdUtilityPool.accrualBlockNumber(), block.number);

        vm.roll(2000);
        assertEq(
            sdUtilityPool.getDelegatorLatestSDBalance(user),
            (cTokenBalance * sdUtilityPool.getLatestExchangeRate()) / 1e18
        );
    }

    function test_RequestWithdraw(
        uint128 sdDelegateAmount,
        uint128 cTokenWithdrawAmount,
        uint16 randomSeed
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdDelegateAmount <= deployerSDBalance / 2 && sdDelegateAmount > 0);
        vm.assume(cTokenWithdrawAmount <= sdDelegateAmount && cTokenWithdrawAmount > 0);

        vm.assume(randomSeed > 0);
        address user = vm.addr(randomSeed);

        staderToken.transfer(user, sdDelegateAmount);
        vm.startPrank(user); // makes user as the caller untill stopPrank();
        staderToken.approve(address(sdUtilityPool), sdDelegateAmount);
        uint256 exchangeRate = sdUtilityPool.getLatestExchangeRate();
        sdUtilityPool.delegate(sdDelegateAmount);
        uint256 cTokenBalance = (1e18 * uint256(sdDelegateAmount)) / exchangeRate;
        uint256 userWithdrawCToken = sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user);
        assertEq(cTokenBalance, sdUtilityPool.delegatorCTokenBalance(user));
        assertEq(userWithdrawCToken, 0);
        vm.expectRevert(ISDUtilityPool.InvalidAmountOfWithdraw.selector);
        sdUtilityPool.requestWithdraw(2 * cTokenBalance);
        vm.prank(staderManager);
        sdUtilityPool.pause();
        vm.startPrank(user);
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.requestWithdraw(cTokenWithdrawAmount / 2);
        vm.prank(staderAdmin);
        sdUtilityPool.unpause();
        vm.startPrank(user);
        uint256 requestID1 = sdUtilityPool.requestWithdraw(cTokenWithdrawAmount / 2);
        uint256 cTokenBalancePostWithdraw1 = sdUtilityPool.delegatorCTokenBalance(user);
        uint256 userWithdrawCTokenPostWithdraw1 = sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user);
        assertEq(requestID1, 1);
        assertEq(cTokenBalancePostWithdraw1, cTokenBalance - cTokenWithdrawAmount / 2);
        assertEq(userWithdrawCTokenPostWithdraw1, cTokenWithdrawAmount / 2);
        vm.prank(staderAdmin);
        sdUtilityPool.updateMaxNonRedeemedDelegatorRequestCount(1);
        vm.startPrank(user);
        vm.expectRevert(ISDUtilityPool.MaxLimitOnWithdrawRequestCountReached.selector);
        sdUtilityPool.requestWithdraw(cTokenWithdrawAmount - cTokenWithdrawAmount / 2);
        vm.prank(staderAdmin);
        sdUtilityPool.updateMaxNonRedeemedDelegatorRequestCount(1000);
        vm.startPrank(user);
        uint256 requestID2 = sdUtilityPool.requestWithdraw(cTokenWithdrawAmount - cTokenWithdrawAmount / 2);
        uint256 cTokenBalancePostWithdraw2 = sdUtilityPool.delegatorCTokenBalance(user);
        uint256 userWithdrawCTokenPostWithdraw2 = sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user);
        assertEq(cTokenBalancePostWithdraw2, cTokenBalance - cTokenWithdrawAmount);
        assertEq(userWithdrawCTokenPostWithdraw2, cTokenWithdrawAmount);
        assertEq(requestID2, 2);
    }

    function test_RequestWithdrawWithSDAmount(
        uint128 sdDelegateAmount,
        uint128 sdWithdrawAmount,
        uint16 randomSeed1,
        uint16 randomSeed2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdDelegateAmount <= deployerSDBalance / 3 && sdDelegateAmount > 0);
        vm.assume(sdWithdrawAmount <= sdDelegateAmount && sdWithdrawAmount > 0);

        vm.assume(randomSeed1 > 0);
        vm.assume(randomSeed2 > 0 && randomSeed2 != randomSeed1);
        address user = vm.addr(randomSeed1);
        address user1 = vm.addr(randomSeed2);

        staderToken.transfer(user, sdDelegateAmount);
        staderToken.transfer(user1, sdDelegateAmount);
        vm.startPrank(user1); // makes user as the caller untill stopPrank();
        staderToken.approve(address(sdUtilityPool), sdDelegateAmount);
        sdUtilityPool.delegate(sdDelegateAmount);
        vm.stopPrank();
        //transfer SD to increase ER
        staderToken.transfer(address(sdUtilityPool), sdWithdrawAmount);
        vm.startPrank(user); // makes user as the caller untill stopPrank();
        staderToken.approve(address(sdUtilityPool), sdDelegateAmount);
        uint256 exchangeRate = sdUtilityPool.getLatestExchangeRate();
        sdUtilityPool.delegate(sdDelegateAmount);
        uint256 cTokenBalance = (1e18 * uint256(sdDelegateAmount)) / exchangeRate;
        assertEq(sdUtilityPool.delegatorCTokenBalance(user), cTokenBalance);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user), 0);
        vm.expectRevert(ISDUtilityPool.InvalidAmountOfWithdraw.selector);
        sdUtilityPool.requestWithdrawWithSDAmount(deployerSDBalance);
        vm.prank(staderManager);
        sdUtilityPool.pause();
        vm.startPrank(user);
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.requestWithdrawWithSDAmount(sdWithdrawAmount / 2);
        vm.prank(staderAdmin);
        sdUtilityPool.unpause();
        vm.startPrank(user);
        uint256 exchangeRatePostDelegation = sdUtilityPool.getLatestExchangeRate();
        uint256 requestID1 = sdUtilityPool.requestWithdrawWithSDAmount(sdWithdrawAmount / 2);
        uint256[] memory requestIds = sdUtilityPool.getRequestIdsByDelegator(user);
        uint256 cTokenToReduce = (uint256(sdWithdrawAmount / 2) * 1e18) / exchangeRatePostDelegation;
        assertEq(requestID1, 1);
        assertEq(requestID1, requestIds[0]);
        assertEq(sdUtilityPool.delegatorCTokenBalance(user), cTokenBalance - cTokenToReduce);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user), cTokenToReduce);
        assertEq(sdUtilityPool.sdRequestedForWithdraw(), sdWithdrawAmount / 2);
    }

    function test_FinalizeDelegatorWithdrawalRequestAndClaim(
        uint128 sdDelegateAmount,
        uint16 randomSeed1,
        uint16 randomSeed2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdDelegateAmount <= deployerSDBalance / 5 && sdDelegateAmount > 0);

        vm.assume(randomSeed1 > 0);
        vm.assume(randomSeed2 > 0 && randomSeed2 != randomSeed1);
        address user1 = vm.addr(randomSeed1);
        address user2 = vm.addr(randomSeed2);

        staderToken.transfer(user1, sdDelegateAmount);
        staderToken.transfer(user2, sdDelegateAmount);
        vm.startPrank(user2); // makes user as the caller untill stopPrank();
        staderToken.approve(address(sdUtilityPool), sdDelegateAmount);
        sdUtilityPool.delegate(sdDelegateAmount);
        vm.stopPrank();
        //transfer SD to increase ER
        staderToken.transfer(address(sdUtilityPool), sdDelegateAmount);
        vm.startPrank(user1); // makes user as the caller untill stopPrank();
        staderToken.approve(address(sdUtilityPool), sdDelegateAmount);
        sdUtilityPool.delegate(sdDelegateAmount);
        uint256 user1CToken = sdUtilityPool.delegatorCTokenBalance(user1);
        uint256 user2CToken = sdUtilityPool.delegatorCTokenBalance(user2);
        uint256 exchangeRatePreWithdraw = sdUtilityPool.getLatestExchangeRate();
        vm.roll(1000);
        sdUtilityPool.requestWithdraw(user1CToken / 2);
        vm.prank(user2);
        sdUtilityPool.requestWithdraw(user2CToken / 2);
        uint256 sdRequestedForWithdraw = ((user1CToken / 2) * exchangeRatePreWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePreWithdraw) /
            1e18;
        staderToken.transfer(address(sdUtilityPool), sdDelegateAmount);
        uint256 exchangeRatePostWithdraw = sdUtilityPool.getLatestExchangeRate();
        vm.roll(2000);
        vm.prank(user1);
        sdUtilityPool.requestWithdraw(user1CToken / 2);
        vm.prank(user2);
        sdUtilityPool.requestWithdraw(user2CToken / 2);
        sdRequestedForWithdraw +=
            ((user1CToken / 2) * exchangeRatePostWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePostWithdraw) /
            1e18;
        assertEq(sdUtilityPool.delegatorCTokenBalance(user1), user1CToken - user1CToken / 2 - user1CToken / 2);
        assertEq(sdUtilityPool.delegatorCTokenBalance(user2), user2CToken - user2CToken / 2 - user2CToken / 2);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user1), user1CToken / 2 + user1CToken / 2);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user2), user2CToken / 2 + user2CToken / 2);
        vm.prank(staderManager);
        sdUtilityPool.pause();
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        vm.startPrank(staderAdmin);
        sdUtilityPool.unpause();
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        assertEq(sdRequestedForWithdraw, sdUtilityPool.sdRequestedForWithdraw());
        assertEq(sdUtilityPool.nextRequestIdToFinalize(), 1);
        assertEq(sdUtilityPool.sdReservedForClaim(), 0);
        sdUtilityPool.updateMinBlockDelayToFinalizeRequest(1000);

        //finalize request 1 and 2
        vm.roll(2500);
        sdRequestedForWithdraw -=
            ((user1CToken / 2) * exchangeRatePreWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePreWithdraw) /
            1e18;
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        assertEq(sdRequestedForWithdraw, sdUtilityPool.sdRequestedForWithdraw());
        assertEq(sdUtilityPool.nextRequestIdToFinalize(), 3);
        assertEq(
            sdUtilityPool.sdReservedForClaim(),
            ((user1CToken / 2) * exchangeRatePreWithdraw) / 1e18 + ((user2CToken / 2) * exchangeRatePreWithdraw) / 1e18
        );
        vm.expectRevert(ISDUtilityPool.CallerNotAuthorizedToRedeem.selector);
        sdUtilityPool.claim(1);
        vm.expectRevert(abi.encodeWithSelector(ISDUtilityPool.RequestIdNotFinalized.selector, 3));
        sdUtilityPool.claim(3);

        //finalize request 3 and 4
        vm.roll(3500);
        sdRequestedForWithdraw -=
            ((user1CToken / 2) * exchangeRatePostWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePostWithdraw) /
            1e18;
        sdUtilityPool.finalizeDelegatorWithdrawalRequest();
        assertEq(sdRequestedForWithdraw, sdUtilityPool.sdRequestedForWithdraw());
        assertEq(sdUtilityPool.nextRequestIdToFinalize(), 5);
        uint256 sdReserveForClaim = ((user1CToken / 2) * exchangeRatePreWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePreWithdraw) /
            1e18 +
            ((user1CToken / 2) * exchangeRatePostWithdraw) /
            1e18 +
            ((user2CToken / 2) * exchangeRatePostWithdraw) /
            1e18;
        assertEq(sdUtilityPool.sdReservedForClaim(), sdReserveForClaim);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user1), 0);
        assertEq(sdUtilityPool.delegatorWithdrawRequestedCTokenCount(user2), 0);
        vm.startPrank(user1);
        sdUtilityPool.claim(1);
        assertEq(staderToken.balanceOf(user1), ((user1CToken / 2) * exchangeRatePreWithdraw) / 1e18);
        assertEq(
            sdUtilityPool.sdReservedForClaim(),
            sdReserveForClaim - ((user1CToken / 2) * exchangeRatePreWithdraw) / 1e18
        );
        vm.expectRevert(ISDUtilityPool.CallerNotAuthorizedToRedeem.selector);
        sdUtilityPool.claim(1);
    }

    function test_Utilize(uint256 utilizeAmount) public {
        vm.assume(utilizeAmount <= sdUtilityPool.maxETHWorthOfSDPerValidator() && utilizeAmount > 0);
        vm.startPrank(staderManager);
        sdUtilityPool.pause();
        sdUtilityPool.updateProtocolFee(1e17);
        vm.stopPrank();
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.utilize(utilizeAmount);
        vm.prank(staderAdmin);
        sdUtilityPool.unpause();
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.convertETHToSD.selector),
            abi.encode(sdUtilityPool.maxETHWorthOfSDPerValidator())
        );
        vm.expectRevert(ISDUtilityPool.SDUtilizeLimitReached.selector);
        sdUtilityPool.utilize(2 * 1 ether);
        vm.expectRevert(ISDUtilityPool.InsufficientPoolBalance.selector);
        sdUtilityPool.utilize(utilizeAmount);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);
        vm.roll(1000);
        assertEq(sdUtilityPool.poolUtilization(), 0);
        sdUtilityPool.utilize(utilizeAmount);
        uint256 poolUtilization = sdUtilityPool.poolUtilization();
        assertEq(
            sdUtilityPool.getDelegationRatePerBlock(),
            (poolUtilization *
                ((sdUtilityPool.utilizationRatePerBlock() * (1e18 - sdUtilityPool.protocolFee())) / 1e18)) / 1e18
        );
        (uint256 principal, uint256 utilizerUtilizedIndex) = sdUtilityPool.utilizerData(address(this));
        assertEq(principal, utilizeAmount);
        vm.roll(11000);
        uint256 utilizerIndex = sdUtilityPool.utilizeIndex() +
            (sdUtilityPool.utilizeIndex() * sdUtilityPool.utilizationRatePerBlock() * 10000) /
            1e18;
        uint256 feeAccumulated = (sdUtilityPool.totalUtilizedSD() * sdUtilityPool.utilizationRatePerBlock() * 10000) /
            1e18;
        uint256 totalUtilizedSDNew = sdUtilityPool.totalUtilizedSD() + feeAccumulated;
        uint256 latestBalance = (principal * utilizerIndex) / utilizerUtilizedIndex;
        uint256 accumulatedProtocolFee = sdUtilityPool.accumulatedProtocolFee() +
            (sdUtilityPool.protocolFee() * feeAccumulated) /
            1e18;
        assertEq(sdUtilityPool.getUtilizerLatestBalance(address(this)), latestBalance);
        sdUtilityPool.accrueFee();
        assertEq(sdUtilityPool.utilizerBalanceStored(address(this)), latestBalance);
        assertEq(sdUtilityPool.utilizerBalanceCurrent(address(this)), latestBalance);

        sdUtilityPool.utilize(utilizeAmount);
        (uint256 principal2, uint256 utilizerUtilizedIndex2) = sdUtilityPool.utilizerData(address(this));
        assertEq(principal2, latestBalance + utilizeAmount);
        assertEq(sdUtilityPool.totalUtilizedSD(), totalUtilizedSDNew + utilizeAmount);
        assertEq(sdUtilityPool.accrualBlockNumber(), 11000);
        assertEq(sdUtilityPool.accumulatedProtocolFee(), accumulatedProtocolFee);
        assertEq(principal2, (principal2 * sdUtilityPool.utilizeIndex()) / utilizerUtilizedIndex2);
        assertEq(principal2, sdUtilityPool.getUtilizerLatestBalance(address(this)));
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.withdrawProtocolFee(accumulatedProtocolFee);
        vm.startPrank(staderManager);
        vm.expectRevert(ISDUtilityPool.InvalidWithdrawAmount.selector);
        sdUtilityPool.withdrawProtocolFee(accumulatedProtocolFee + 1);
        uint256 moreSDThanAvailable = sdUtilityPool.getPoolAvailableSDBalance() + 1;
        vm.expectRevert(ISDUtilityPool.InvalidWithdrawAmount.selector);
        sdUtilityPool.withdrawProtocolFee(moreSDThanAvailable);
        sdUtilityPool.withdrawProtocolFee(accumulatedProtocolFee);
        assertEq(sdUtilityPool.accumulatedProtocolFee(), 0);
        assertEq(staderToken.balanceOf(staderTreasury), accumulatedProtocolFee);
        sdUtilityPool.withdrawProtocolFee(sdUtilityPool.accumulatedProtocolFee());
        sdUtilityPool.pause();
        uint256 latestAccumulatedProtocolFee = sdUtilityPool.accumulatedProtocolFee();
        vm.expectRevert('Pausable: paused');
        sdUtilityPool.withdrawProtocolFee(latestAccumulatedProtocolFee);
    }

    function test_UtilizeWhileAddingKeys(
        uint16 randomSeed,
        uint128 utilizeAmount,
        uint128 nonTerminalKeyCount
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(randomSeed > 0);
        vm.assume(utilizeAmount < deployerSDBalance / 10);
        address permissionlessNodeRegistry = vm.addr(99);
        vm.prank(staderAdmin);
        staderConfig.updatePermissionlessNodeRegistry(permissionlessNodeRegistry);
        uint256 maxUtilize = uint256(nonTerminalKeyCount) * sdUtilityPool.maxETHWorthOfSDPerValidator();
        vm.assume(uint256(nonTerminalKeyCount) * uint256(utilizeAmount) < maxUtilize);
        address user = vm.addr(randomSeed);
        staderToken.transfer(address(sdUtilityPool), deployerSDBalance);
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        sdUtilityPool.utilizeWhileAddingKeys(user, utilizeAmount, nonTerminalKeyCount);
        vm.startPrank(permissionlessNodeRegistry);
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.convertETHToSD.selector),
            abi.encode(sdUtilityPool.maxETHWorthOfSDPerValidator())
        );
        vm.expectRevert(ISDUtilityPool.SDUtilizeLimitReached.selector);
        sdUtilityPool.utilizeWhileAddingKeys(user, maxUtilize + 1, nonTerminalKeyCount);
        vm.startPrank(user);
        vm.roll(1000);
        sdUtilityPool.utilize(sdUtilityPool.maxETHWorthOfSDPerValidator());
        (uint256 principal1, uint256 utilizeIndex1) = sdUtilityPool.utilizerData(user);
        assertEq(principal1, sdUtilityPool.maxETHWorthOfSDPerValidator());
        vm.roll(2000);
        uint256 utilizerIndexLatest = sdUtilityPool.utilizeIndex() +
            (sdUtilityPool.utilizeIndex() * sdUtilityPool.utilizationRatePerBlock() * 1000) /
            1e18;
        assertEq(sdUtilityPool.getUtilizerLatestBalance(user), (principal1 * utilizerIndexLatest) / utilizeIndex1);
        vm.startPrank(permissionlessNodeRegistry);
        sdUtilityPool.utilizeWhileAddingKeys(user, utilizeAmount, nonTerminalKeyCount);
        (uint256 principal2, uint256 utilizeIndex2) = sdUtilityPool.utilizerData(user);
        assertEq(principal2, (principal1 * utilizerIndexLatest) / utilizeIndex1 + utilizeAmount);
        assertEq(utilizeIndex2, utilizerIndexLatest);
        assertEq(utilizeIndex2, sdUtilityPool.utilizeIndex());

        vm.roll(3000);
        uint256 utilizerIndexLatest2 = sdUtilityPool.utilizeIndex() +
            (sdUtilityPool.utilizeIndex() * sdUtilityPool.utilizationRatePerBlock() * 1000) /
            1e18;
        sdUtilityPool.utilizeWhileAddingKeys(user, utilizeAmount, nonTerminalKeyCount);
        (uint256 principal3, uint256 utilizeIndex3) = sdUtilityPool.utilizerData(user);
        assertEq(principal3, (principal2 * utilizerIndexLatest2) / utilizeIndex2 + utilizeAmount);
        assertEq(utilizeIndex3, utilizerIndexLatest2);
        assertEq(utilizeIndex3, sdUtilityPool.utilizeIndex());
    }

    function test_Repay(
        uint8 randomSeed,
        uint128 utilizeAmount,
        uint128 repayAmount
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(randomSeed > 0);
        vm.assume(utilizeAmount < deployerSDBalance / 4);
        address user = vm.addr(randomSeed);
        staderToken.transfer(address(sdUtilityPool), deployerSDBalance / 4);
        staderToken.transfer(user, deployerSDBalance / 2);
        vm.startPrank(user);
        staderToken.approve(address(sdUtilityPool), deployerSDBalance / 2);
        vm.roll(1000);
        uint256 keyCountToUtilize = uint256(utilizeAmount) / sdUtilityPool.maxETHWorthOfSDPerValidator() + 1;
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.getOperatorInfo.selector),
            abi.encode(1, 1, keyCountToUtilize)
        );
        sdUtilityPool.utilize(utilizeAmount);
        (uint256 principal1, uint256 utilizeIndex1) = sdUtilityPool.utilizerData(user);
        vm.roll(2000);
        uint256 latestBalance = sdUtilityPool.getUtilizerLatestBalance(user);

        uint256 fee = latestBalance - utilizeAmount;
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );
        (uint256 repaidAmount, uint256 feePaid) = sdUtilityPool.repay(repayAmount);
        uint256 actualRepayAmount = Math.min(latestBalance, repayAmount);
        uint256 actualFeePaid = Math.min(fee, repayAmount);
        assertEq(repaidAmount, actualRepayAmount);
        assertEq(feePaid, actualFeePaid);
        (uint256 principal2, uint256 utilizeIndex2) = sdUtilityPool.utilizerData(user);
        assertEq(principal2, (principal1 * utilizeIndex2) / utilizeIndex1 - actualRepayAmount);
    }

    function test_RepayOnBehalf(
        uint8 randomSeed,
        uint128 utilizeAmount,
        uint128 repayAmount
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(randomSeed > 0);
        vm.assume(utilizeAmount < deployerSDBalance / 4);
        address user = vm.addr(randomSeed);
        staderToken.transfer(address(sdUtilityPool), deployerSDBalance / 4);
        vm.startPrank(user);
        vm.roll(1000);
        uint256 keyCountToUtilize = uint256(utilizeAmount) / sdUtilityPool.maxETHWorthOfSDPerValidator() + 1;
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.getOperatorInfo.selector),
            abi.encode(1, 1, keyCountToUtilize)
        );
        sdUtilityPool.utilize(utilizeAmount);
        (uint256 principal1, uint256 utilizeIndex1) = sdUtilityPool.utilizerData(user);
        vm.stopPrank();
        staderToken.approve(address(sdUtilityPool), deployerSDBalance / 2);
        vm.roll(2000);
        uint256 latestBalance = sdUtilityPool.getUtilizerLatestBalance(user);

        uint256 fee = latestBalance - utilizeAmount;
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );
        (uint256 repaidAmount, uint256 feePaid) = sdUtilityPool.repayOnBehalf(user, repayAmount);
        uint256 actualRepayAmount = Math.min(latestBalance, repayAmount);
        uint256 actualFeePaid = Math.min(fee, repayAmount);
        assertEq(repaidAmount, actualRepayAmount);
        assertEq(feePaid, actualFeePaid);
        (uint256 principal2, uint256 utilizeIndex2) = sdUtilityPool.utilizerData(user);
        assertEq(principal2, (principal1 * utilizeIndex2) / utilizeIndex1 - actualRepayAmount);
    }

    function test_MaxApproveSD() public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.maxApproveSD();
        vm.startPrank(staderManager);
        vm.mockCall(
            address(staderConfig),
            abi.encodeWithSelector(IStaderConfig.getSDCollateral.selector),
            abi.encode(address(0))
        );
        vm.expectRevert(UtilLib.ZeroAddress.selector);
        sdUtilityPool.maxApproveSD();
        vm.mockCall(
            address(staderConfig),
            abi.encodeWithSelector(IStaderConfig.getSDCollateral.selector),
            abi.encode(address(sdCollateral))
        );
        sdUtilityPool.maxApproveSD();
        assertEq(staderToken.allowance(address(sdUtilityPool), address(sdCollateral)), type(uint256).max);
    }

    function test_UpdateProtocolFee(uint128 protocolFee) public {
        uint256 maxProtocolFee = sdUtilityPool.MAX_PROTOCOL_FEE();
        vm.assume(protocolFee < maxProtocolFee);
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.updateProtocolFee(protocolFee);
        vm.startPrank(staderManager);
        vm.expectRevert(ISDUtilityPool.InvalidInput.selector);
        sdUtilityPool.updateProtocolFee(1e18);
        sdUtilityPool.updateProtocolFee(protocolFee);
        assertEq(sdUtilityPool.protocolFee(), protocolFee);
    }

    function test_UpdateUtilizationRatePerBlock(uint128 utilizationRate) public {
        uint256 maxUtilizationRatePerBlock = sdUtilityPool.MAX_UTILIZATION_RATE_PER_BLOCK();
        vm.assume(utilizationRate < maxUtilizationRatePerBlock);
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.updateUtilizationRatePerBlock(utilizationRate);
        vm.startPrank(staderManager);
        vm.expectRevert(ISDUtilityPool.InvalidInput.selector);
        sdUtilityPool.updateUtilizationRatePerBlock(maxUtilizationRatePerBlock + 1);
        sdUtilityPool.updateUtilizationRatePerBlock(utilizationRate);
        assertEq(sdUtilityPool.utilizationRatePerBlock(), utilizationRate);
    }

    function test_UpdateMaxETHWorthOfSDPerValidator(uint128 maxETHWorthOfSD) public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.updateMaxETHWorthOfSDPerValidator(maxETHWorthOfSD);
        vm.startPrank(staderManager);
        sdUtilityPool.updateMaxETHWorthOfSDPerValidator(maxETHWorthOfSD);
        assertEq(sdUtilityPool.maxETHWorthOfSDPerValidator(), maxETHWorthOfSD);
    }

    function test_UpdateFinalizationBatchLimit(uint128 finalizationBatchLimit) public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdUtilityPool.updateFinalizationBatchLimit(finalizationBatchLimit);
        vm.startPrank(staderManager);
        sdUtilityPool.updateFinalizationBatchLimit(finalizationBatchLimit);
        assertEq(sdUtilityPool.finalizationBatchLimit(), finalizationBatchLimit);
    }

    function test_UpdateStaderConfig(uint16 randomSeed) public {
        vm.assume(randomSeed > 0);
        address inputAddr = vm.addr(randomSeed);
        vm.expectRevert();
        sdUtilityPool.updateStaderConfig(inputAddr);
        vm.prank(staderAdmin);
        sdUtilityPool.updateStaderConfig(inputAddr);
        assertEq(address(sdUtilityPool.staderConfig()), inputAddr);
    }

    function test_UpdateRiskConfig(uint256 randomSeed) public {
        vm.assume(randomSeed > 0);
        vm.assume(randomSeed < 100);
        vm.expectRevert();
        sdUtilityPool.updateRiskConfig(randomSeed, randomSeed, randomSeed, randomSeed);
        vm.prank(staderAdmin);
        sdUtilityPool.updateRiskConfig(randomSeed, randomSeed, randomSeed, randomSeed);
    }

    function test_LiquidationCall(uint16 randomSeed) public {
        vm.assume(randomSeed > 1);
        uint256 utilizeAmount = 1e22;

        address operator = vm.addr(randomSeed);
        address liquidator = vm.addr(randomSeed - 1);

        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        staderToken.transfer(liquidator, utilizeAmount * 10);
        sdUtilityPool.delegate(utilizeAmount * 10);

        vm.startPrank(operator);
        sdUtilityPool.utilize(utilizeAmount);
        vm.stopPrank();

        vm.roll(200000000);
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.operatorUtilizedSDBalance.selector),
            abi.encode(utilizeAmount)
        );

        vm.startPrank(liquidator);
        staderToken.approve(address(sdUtilityPool), utilizeAmount * 10);
        uint256 beforeBalance = staderToken.balanceOf(liquidator);
        UserData memory userData = sdUtilityPool.getUserData(operator);
        sdUtilityPool.liquidationCall(operator);
        vm.stopPrank();

        uint256 afterBalance = staderToken.balanceOf(liquidator);
        assertEq(beforeBalance - afterBalance, userData.totalInterestSD);

        userData = sdUtilityPool.getUserData(operator);
        assertEq(0, userData.totalInterestSD);
    }
}
