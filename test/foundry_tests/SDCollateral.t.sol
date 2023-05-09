pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/Auction.sol';
import '../../contracts/SDCollateral.sol';

import '../mocks/StaderTokenMock.sol';
import '../mocks/PoolUtilsMock.sol';
import '../mocks/StaderOracleMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract SDCollateralTest is Test {
    address staderAdmin;
    address staderManager;

    SDCollateral sdCollateral;
    StaderConfig staderConfig;
    StaderTokenMock staderToken;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

        PoolUtilsMock poolUtils = new PoolUtilsMock();
        StaderOracleMock staderOracle = new StaderOracleMock();

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

        Auction auctionImpl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(auctionImpl), address(admin), '');
        Auction auction = Auction(address(proxy));
        auction.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updateAuctionContract(address(auction));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        SDCollateral collateralImpl = new SDCollateral();
        TransparentUpgradeableProxy collateralProxy = new TransparentUpgradeableProxy(
            address(collateralImpl),
            address(admin),
            ''
        );
        sdCollateral = SDCollateral(address(collateralProxy));
        sdCollateral.initialize(staderAdmin, address(staderConfig));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        SDCollateral collateralImpl = new SDCollateral();
        TransparentUpgradeableProxy collateralProxy = new TransparentUpgradeableProxy(
            address(collateralImpl),
            address(admin),
            ''
        );
        SDCollateral sdCollateral2 = SDCollateral(address(collateralProxy));
        sdCollateral2.initialize(staderAdmin, address(staderConfig));
    }

    function test_sdCollateralInitialize() public {
        assertEq(address(sdCollateral.staderConfig()), address(staderConfig));
        assertEq(staderConfig.getStaderToken(), address(staderToken));
        assertNotEq(staderConfig.getPoolUtils(), address(0));
        assertEq(staderConfig.getPoolSelector(), address(0));
        assertTrue(sdCollateral.hasRole(sdCollateral.DEFAULT_ADMIN_ROLE(), staderAdmin));
        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }

    function testFail_depositSDAsCollateral_withInsufficientApproval(uint256 approveAmount, uint256 sdAmount) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        vm.assume(approveAmount < sdAmount);
        staderToken.approve(address(sdCollateral), approveAmount);
        sdCollateral.depositSDAsCollateral(sdAmount);
    }

    function test_depositSDAsCollateral(
        uint128 approveAmount,
        uint128 sdAmount,
        uint16 randomSeed
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        vm.assume(randomSeed > 0);
        address user = vm.addr(randomSeed);

        staderToken.transfer(user, sdAmount);

        vm.startPrank(user); // makes user as the caller untill stopPrank();
        vm.assume(approveAmount >= sdAmount);
        staderToken.approve(address(sdCollateral), approveAmount);
        sdCollateral.depositSDAsCollateral(sdAmount);
        assertEq(sdCollateral.totalSDCollateral(), sdAmount);
        assertEq(sdCollateral.operatorSDBalance(user), sdAmount);
        assertEq(staderToken.balanceOf(address(sdCollateral)), sdAmount);
    }

    function test_updatePoolThreshold_revertIfNotCalledByManager(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _maxThreshold,
        uint256 _withdrawThreshold
    ) public {
        // not called by manager
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        sdCollateral.updatePoolThreshold(_poolId, _minThreshold, _maxThreshold, _withdrawThreshold, 'ETH');
    }

    function test_updatePoolThreshold_revertIfMinThresholdGTMaxThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _maxThreshold,
        uint256 _withdrawThreshold
    ) public {
        vm.assume(_minThreshold > _maxThreshold);
        vm.prank(staderManager);
        vm.expectRevert(ISDCollateral.InvalidPoolLimit.selector);
        sdCollateral.updatePoolThreshold(_poolId, _minThreshold, _maxThreshold, _withdrawThreshold, 'ETH');
    }

    function test_updatePoolThreshold_revertIfMinThresholdGTWithdrawThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _maxThreshold,
        uint256 _withdrawThreshold
    ) public {
        vm.assume(_minThreshold > _withdrawThreshold);
        vm.prank(staderManager);
        vm.expectRevert(ISDCollateral.InvalidPoolLimit.selector);
        sdCollateral.updatePoolThreshold(_poolId, _minThreshold, _maxThreshold, _withdrawThreshold, 'ETH');
    }

    function test_updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _maxThreshold,
        uint256 _withdrawThreshold
    ) public {
        vm.assume(_minThreshold <= _maxThreshold && _minThreshold <= _withdrawThreshold);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(_poolId, _minThreshold, _maxThreshold, _withdrawThreshold, 'ETH');

        (uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold, string memory units) = sdCollateral
            .poolThresholdbyPoolId(_poolId);

        assertEq(minThreshold, _minThreshold);
        assertEq(maxThreshold, _maxThreshold);
        assertEq(withdrawThreshold, _withdrawThreshold);
        assertEq(units, 'ETH');
    }

    function test_requestWithdraw_revertIfPoolThresholdNotSet(uint256 _requestedSD) public {
        vm.expectRevert(ISDCollateral.InvalidPoolId.selector);
        sdCollateral.requestWithdraw(_requestedSD);
    }

    function test_requestWithdraw_reverts_InsufficientSDToWithdraw(uint128 _depositSDAmount, uint128 _requestedSD)
        public
    {
        // set poolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        // assuming deployer is operator
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(_depositSDAmount <= deployerSDBalance);

        staderToken.approve(address(sdCollateral), _depositSDAmount);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        uint256 validatorCount = 5; // set in PoolUtilsMock::getOperatorTotalNonTerminalKeys
        uint256 sdWithdrawableThreshold = sdCollateral.convertETHToSD(withdrawThreshold * validatorCount);

        vm.assume(_depositSDAmount < sdWithdrawableThreshold + _requestedSD);

        vm.expectRevert(abi.encodeWithSelector(ISDCollateral.InsufficientSDToWithdraw.selector, _depositSDAmount));
        sdCollateral.requestWithdraw(_requestedSD);
    }

    function test_requestWithdraw(
        uint128 _depositSDAmount,
        uint128 _requestedSD1,
        uint128 _requestedSD2
    ) public {
        // set poolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        // assuming deployer is operator
        address operator = address(this);
        uint256 deployerSDBalance = staderToken.balanceOf(operator);
        vm.assume(_depositSDAmount <= deployerSDBalance);

        staderToken.approve(address(sdCollateral), _depositSDAmount);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        uint256 validatorCount = 5; // set in PoolUtilsMock::getOperatorTotalNonTerminalKeys
        uint256 sdWithdrawableThreshold = sdCollateral.convertETHToSD(withdrawThreshold * validatorCount);

        vm.assume(_depositSDAmount >= sdWithdrawableThreshold + _requestedSD1 + _requestedSD2);

        (uint256 lastWithdrawReqTimestamp, uint256 totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, 0);
        assertEq(totalSDWithdrawReqAmount, 0);
        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);

        sdCollateral.requestWithdraw(_requestedSD1);

        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, _requestedSD1);

        // operator requestWithdraw again after sometime
        skip(2 hours);
        sdCollateral.requestWithdraw(_requestedSD2);

        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, _requestedSD1 + _requestedSD2);
    }

    function test_claimWithdraw_reverts_if_no_more_requests(uint128 _depositSDAmount) public {
        // set poolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(_depositSDAmount <= deployerSDBalance);
        staderToken.approve(address(sdCollateral), _depositSDAmount);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        vm.expectRevert(); // Arithmetic over/underflow  || AlreadyClaimed
        sdCollateral.claimWithdraw();
    }

    function test_setWithdrawDelay(uint256 _withdrawDelay) public {
        vm.startPrank(staderManager); // called by staderManager for all contract calls ahead until stopPrank()

        vm.expectRevert(ISDCollateral.NoStateChange.selector);
        sdCollateral.setWithdrawDelay(0);

        vm.assume(_withdrawDelay > 0);
        sdCollateral.setWithdrawDelay(_withdrawDelay);

        vm.expectRevert(ISDCollateral.NoStateChange.selector);
        sdCollateral.setWithdrawDelay(_withdrawDelay);
    }

    function test_claimWithdraw_reverts_if_ClaimNotReady(
        uint32 _withdrawDelay,
        uint32 _actualDelay,
        uint128 _depositSDAmount,
        uint128 _requestedSD
    ) public {
        vm.assume(_withdrawDelay > 0);
        vm.prank(staderManager);
        sdCollateral.setWithdrawDelay(_withdrawDelay);

        // set poolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        // assuming deployer is operator
        address operator = address(this);
        uint256 deployerSDBalance = staderToken.balanceOf(operator);
        vm.assume(_depositSDAmount <= deployerSDBalance);

        staderToken.approve(address(sdCollateral), _depositSDAmount);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        uint256 validatorCount = 5; // set in PoolUtilsMock::getOperatorTotalNonTerminalKeys
        uint256 sdWithdrawableThreshold = sdCollateral.convertETHToSD(withdrawThreshold * validatorCount);

        vm.assume(_requestedSD > 0);
        vm.assume(_depositSDAmount >= sdWithdrawableThreshold + _requestedSD);
        sdCollateral.requestWithdraw(_requestedSD);

        // at any time before withdrawDelay
        vm.assume(_actualDelay < _withdrawDelay);
        skip(_actualDelay);
        vm.expectRevert(ISDCollateral.ClaimNotReady.selector);
        sdCollateral.claimWithdraw();
    }

    function test_claimWithdraw(
        uint64 _actualDelay,
        uint256 _depositSDAmount,
        uint256 _requestedSD1,
        uint256 _requestedSD2
    ) public {
        vm.assume(_depositSDAmount < type(uint128).max);
        vm.assume(_requestedSD1 < type(uint128).max);
        vm.assume(_requestedSD2 < type(uint128).max);

        vm.prank(staderManager);
        sdCollateral.setWithdrawDelay(3 days);

        // set poolThreshold
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(1, 4e17, 2e18, 1e18, 'ETH');

        // assuming deployer is operator
        address operator = address(this);
        uint256 deployerSDBalance = staderToken.balanceOf(operator);
        vm.assume(_depositSDAmount <= deployerSDBalance);

        staderToken.approve(address(sdCollateral), type(uint256).max);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        uint256 validatorCount = 5; // set in PoolUtilsMock::getOperatorTotalNonTerminalKeys
        uint256 sdWithdrawableThreshold = sdCollateral.convertETHToSD(1e18 * validatorCount);

        vm.assume(_requestedSD1 + _requestedSD2 > 0);
        vm.assume(_depositSDAmount >= sdWithdrawableThreshold + _requestedSD1 + _requestedSD2);

        (uint256 lastWithdrawReqTimestamp, uint256 totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, 0);
        assertEq(totalSDWithdrawReqAmount, 0);
        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);

        sdCollateral.requestWithdraw(_requestedSD1);

        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, _requestedSD1);

        // operator requestWithdraw again after sometime
        skip(2 hours);
        sdCollateral.requestWithdraw(_requestedSD2);

        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, _requestedSD1 + _requestedSD2);

        // at any time after withdrawDelay = 3 days
        vm.assume(_actualDelay > 3 days);
        skip(_actualDelay);

        uint256 sdBalanceBefore = staderToken.balanceOf(operator);
        sdCollateral.claimWithdraw();

        assertEq(staderToken.balanceOf(operator), sdBalanceBefore + _requestedSD1 + _requestedSD2);
        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount - _requestedSD1 - _requestedSD2);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount - _requestedSD1 - _requestedSD2);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp - _actualDelay);
        assertEq(totalSDWithdrawReqAmount, 0);
    }

    function test_claimWithdraw_receivedLessAmount_or_reverts(uint256 _depositSDAmount, uint256 _requestedSD) public {
        vm.assume(_depositSDAmount < type(uint128).max);
        vm.assume(_requestedSD < type(uint128).max);

        vm.prank(staderManager);
        sdCollateral.setWithdrawDelay(3 days);

        // set poolThreshold
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(1, 4e17, 2e18, 1e18, 'ETH');

        // assuming deployer is operator
        address operator = address(this);
        uint256 deployerSDBalance = staderToken.balanceOf(operator);
        vm.assume(_depositSDAmount <= deployerSDBalance);

        staderToken.approve(address(sdCollateral), type(uint256).max);
        sdCollateral.depositSDAsCollateral(_depositSDAmount);

        uint256 validatorCount = 5; // set in PoolUtilsMock::getOperatorTotalNonTerminalKeys
        uint256 totalSDWithdrawThreshold = sdCollateral.convertETHToSD(1e18 * validatorCount);

        vm.assume(_requestedSD > 0);
        vm.assume(_depositSDAmount >= totalSDWithdrawThreshold + _requestedSD);

        sdCollateral.requestWithdraw(_requestedSD);

        uint64 _actualDelay = 3 days + 1;
        skip(_actualDelay);

        // operator adds more validator
        PoolUtilsMock poolUtils = PoolUtilsMock(staderConfig.getPoolUtils());
        poolUtils.updateOperatorTotalNonTerminalKeys(true, 1); // increase validator count by 1
        totalSDWithdrawThreshold = sdCollateral.convertETHToSD(1e18 * 6);

        if (sdCollateral.operatorSDBalance(operator) <= totalSDWithdrawThreshold) {
            // arithmeticError || AlreadyClaimed
            vm.expectRevert();
            sdCollateral.claimWithdraw();
            return;
        }

        uint256 sdBalanceBefore = staderToken.balanceOf(operator);
        uint256 withdrawableSD = sdCollateral.operatorSDBalance(operator) - totalSDWithdrawThreshold;
        uint256 claimableSD = Math.min(_requestedSD, withdrawableSD);
        sdCollateral.claimWithdraw();

        assertTrue(staderToken.balanceOf(operator) <= sdBalanceBefore + _requestedSD);
        assertEq(staderToken.balanceOf(operator), sdBalanceBefore + claimableSD);
        assertEq(sdCollateral.totalSDCollateral(), _depositSDAmount - claimableSD);
        assertEq(sdCollateral.operatorSDBalance(operator), _depositSDAmount - claimableSD);
        (uint256 lastWithdrawReqTimestamp, uint256 totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp - _actualDelay);
        assertEq(totalSDWithdrawReqAmount, 0);
    }

    function test_slashValidatorSD_reverts_when_CallerNotWithdrawVault(uint64 randomSeed) public {
        vm.assume(randomSeed > 0);
        vm.prank(vm.addr(randomSeed));
        vm.expectRevert(UtilLib.CallerNotWithdrawVault.selector);
        sdCollateral.slashValidatorSD(1, 1);
    }

    function test_slashValidatorSD_reverts_when_PoolThresholdNotSet() public {
        address validatorWithdrawVault = address(1); // have set the same in NodeRegistryMock
        vm.prank(validatorWithdrawVault);
        vm.expectRevert(ISDCollateral.InvalidPoolId.selector);
        sdCollateral.slashValidatorSD(1, 1);
    }

    function test_slashValidatorSD_auctionLotNotCreated_whenNoCollateral() public {
        // set poolThreshold
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(1, 4e17, 2e18, 1e18, 'ETH');

        address validatorWithdrawVault = address(1); // have set the same in NodeRegistryMock
        address operator = address(500);
        IAuction auction = IAuction(staderConfig.getAuctionContract());

        // 0 collateral
        assertEq(sdCollateral.operatorSDBalance(operator), 0);
        assertEq(auction.nextLot(), 1);

        vm.prank(validatorWithdrawVault);
        sdCollateral.slashValidatorSD(1, 1);

        assertEq(auction.nextLot(), 1);
    }

    function test_slashValidatorSD() public {
        // set poolThreshold
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(1, 4e17, 2e18, 1e18, 'ETH');

        address validatorWithdrawVault = address(1); // have set the same in NodeRegistryMock
        address operator = address(500);
        Auction auction = Auction(staderConfig.getAuctionContract());

        uint256 sdForOneValidator = sdCollateral.getMinimumSDToBond(1, 1);
        uint256 depositSDAmount = sdForOneValidator + 5;

        staderToken.transfer(operator, depositSDAmount);

        vm.startPrank(operator);
        staderToken.approve(address(sdCollateral), depositSDAmount);
        sdCollateral.depositSDAsCollateral(depositSDAmount);
        vm.stopPrank();

        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount);
        assertEq(auction.nextLot(), 1);

        vm.prank(validatorWithdrawVault);
        vm.expectRevert('ERC20: insufficient allowance');
        sdCollateral.slashValidatorSD(1, 1);

        vm.prank(staderManager);
        sdCollateral.maxApproveSD(address(auction));

        vm.prank(validatorWithdrawVault);
        sdCollateral.slashValidatorSD(1, 1);

        assertEq(auction.nextLot(), 2);
        assertEq(sdCollateral.totalSDCollateral(), 5);
        assertEq(sdCollateral.operatorSDBalance(operator), 5);

        (uint256 _startBlock, uint256 _endBlock, uint256 _sdAmount, , , bool sdClaimed, bool ethExtracted) = auction
            .lots(1);
        assertEq(_startBlock, block.number);
        assertEq(_endBlock, block.number + auction.duration());
        assertEq(_sdAmount, sdForOneValidator);
        assertEq(staderToken.balanceOf(address(auction)), sdForOneValidator);
        assertFalse(sdClaimed);
        assertFalse(ethExtracted);

        // slash once more
        // NOTE: able to slash again using same validator vault
        vm.prank(validatorWithdrawVault);
        sdCollateral.slashValidatorSD(1, 1);

        assertEq(auction.nextLot(), 3);
        assertEq(sdCollateral.totalSDCollateral(), 0);
        assertEq(sdCollateral.operatorSDBalance(operator), 0);

        (_startBlock, _endBlock, _sdAmount, , , sdClaimed, ethExtracted) = auction.lots(2);
        assertEq(_startBlock, block.number);
        assertEq(_endBlock, block.number + auction.duration());
        assertEq(_sdAmount, 5);
        assertEq(staderToken.balanceOf(address(auction)), depositSDAmount);
        assertFalse(sdClaimed);
        assertFalse(ethExtracted);
    }

    function test_updateStaderConfig() public {
        // not DEFAULT_ADMIN_ROLE
        vm.expectRevert();
        sdCollateral.updateStaderConfig(vm.addr(203));

        vm.startPrank(staderAdmin);

        vm.expectRevert(ISDCollateral.NoStateChange.selector);
        sdCollateral.updateStaderConfig(address(staderConfig));

        sdCollateral.updateStaderConfig(vm.addr(203));
        assertEq(address(sdCollateral.staderConfig()), vm.addr(203));
    }

    function test_getRemainingSDToBond(uint256 numValidator, uint256 depositSDAmount) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(depositSDAmount <= deployerSDBalance);
        vm.assume(numValidator < type(uint64).max);

        address operator = address(this);

        // pool Threshold not set
        vm.expectRevert(ISDCollateral.InvalidPoolId.selector);
        uint256 actualRemaniningSDToBond = sdCollateral.getRemainingSDToBond(operator, 1, numValidator);

        // set PoolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        staderToken.approve(address(sdCollateral), depositSDAmount);
        sdCollateral.depositSDAsCollateral(depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount);

        uint256 minimumSDToBond = sdCollateral.convertETHToSD(minThreshold * numValidator);
        uint256 remainingSDToBond = (depositSDAmount >= minimumSDToBond ? 0 : minimumSDToBond - depositSDAmount);
        actualRemaniningSDToBond = sdCollateral.getRemainingSDToBond(operator, poolId, numValidator);
        assertEq(actualRemaniningSDToBond, remainingSDToBond);

        // test has enoughSDCollateral
        assertEq(sdCollateral.hasEnoughSDCollateral(operator, poolId, numValidator), (remainingSDToBond == 0));
    }

    function test_getRewardEligibleSD(uint256 depositSDAmount) public {
        uint256 numValidator = 5; // set in poolUtils mock
        address operator = address(this);

        uint256 deployerSDBalance = staderToken.balanceOf(operator);
        vm.assume(depositSDAmount <= deployerSDBalance);

        // set PoolThreshold
        (uint8 poolId, uint256 minThreshold, uint256 maxThreshold, uint256 withdrawThreshold) = (1, 4e17, 2e18, 1e18);
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(poolId, minThreshold, maxThreshold, withdrawThreshold, 'ETH');

        staderToken.approve(address(sdCollateral), depositSDAmount);
        sdCollateral.depositSDAsCollateral(depositSDAmount);
        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount);

        uint256 totalMinThreshold = numValidator * sdCollateral.convertETHToSD(minThreshold);
        uint256 totalMaxThreshold = numValidator * sdCollateral.convertETHToSD(maxThreshold);

        uint256 rewardEligibleSD = (
            depositSDAmount < totalMinThreshold ? 0 : Math.min(depositSDAmount, totalMaxThreshold)
        );

        assertEq(sdCollateral.getRewardEligibleSD(operator), rewardEligibleSD);
    }

    // NOTE: used uint128 to avoid overflow/underflow
    function test_sd_eth_converters(uint128 _ethAmount) public {
        uint256 sdAmount = sdCollateral.convertETHToSD(_ethAmount);

        // have set 1 eth = 1600 sd in oracle mock
        assertEq(sdAmount, _ethAmount * uint256(1600));

        uint256 ethAmount = sdCollateral.convertSDToETH(sdAmount);
        assertEq(_ethAmount, ethAmount);
    }

    function test_request_slash_claim_sd(uint256 requestedSD, uint128 surplusDeposit) public {
        // set poolThreshold
        vm.prank(staderManager);
        sdCollateral.updatePoolThreshold(1, 4e17, 2e18, 1e18, 'ETH');

        address validatorWithdrawVault = address(1); // have set the same in NodeRegistryMock
        address operator = address(500);
        Auction auction = Auction(staderConfig.getAuctionContract());

        uint256 sdForOneValidator = sdCollateral.getMinimumSDToBond(1, 1);
        uint256 totalWithdrawalableThresholdInSD = sdCollateral.convertETHToSD(5 ether); // numValidator * withdrawThreshold
        uint256 depositSDAmount = totalWithdrawalableThresholdInSD + surplusDeposit;
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(depositSDAmount <= deployerSDBalance);
        staderToken.transfer(operator, depositSDAmount);

        vm.startPrank(operator);
        staderToken.approve(address(sdCollateral), depositSDAmount);
        sdCollateral.depositSDAsCollateral(depositSDAmount);

        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount);
        vm.assume(requestedSD <= surplusDeposit);
        vm.assume(requestedSD > 0);
        sdCollateral.requestWithdraw(requestedSD);
        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount);
        (uint256 lastWithdrawReqTimestamp, uint256 totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, requestedSD);
        vm.stopPrank();

        // let's have one slashing
        vm.prank(staderManager);
        sdCollateral.maxApproveSD(address(auction));

        assertEq(auction.nextLot(), 1);

        vm.prank(validatorWithdrawVault);
        sdCollateral.slashValidatorSD(1, 1); // uint256 _validatorId, uint8 _poolId
        // manually decrement validator to mimic actual scenario
        PoolUtilsMock poolUtils = PoolUtilsMock(staderConfig.getPoolUtils());
        poolUtils.updateOperatorTotalNonTerminalKeys(false, 1); // decrease validator count by 1

        assertEq(auction.nextLot(), 2);
        (, , uint256 _sdAmount, , , , ) = auction.lots(1);
        assertEq(_sdAmount, sdForOneValidator);

        assertEq(sdCollateral.totalSDCollateral(), depositSDAmount - sdForOneValidator);
        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount - sdForOneValidator);

        // requestedAmount still remains the same after slashing
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp);
        assertEq(totalSDWithdrawReqAmount, requestedSD);

        vm.prank(staderManager);
        sdCollateral.setWithdrawDelay(3 days);

        skip(3 days + 1);

        uint256 sdBalanceBefore = staderToken.balanceOf(operator);
        vm.prank(operator);
        sdCollateral.claimWithdraw();

        assertEq(staderToken.balanceOf(operator), sdBalanceBefore + requestedSD);
        assertEq(sdCollateral.totalSDCollateral(), depositSDAmount - sdForOneValidator - requestedSD);
        assertEq(sdCollateral.operatorSDBalance(operator), depositSDAmount - sdForOneValidator - requestedSD);
        (lastWithdrawReqTimestamp, totalSDWithdrawReqAmount) = sdCollateral.withdrawReq(operator);
        assertEq(lastWithdrawReqTimestamp, block.timestamp - 3 days - 1);
        assertEq(totalSDWithdrawReqAmount, 0);
    }
}
