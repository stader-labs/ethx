pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/SDCollateral.sol';

import '../mocks/StaderTokenMock.sol';

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
        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
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
}
