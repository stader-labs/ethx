pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderInsuranceFund.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/PermissionedPoolMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderInsuranceFundTest is Test {
    address staderAdmin;
    address staderManager;

    ProxyAdmin proxyAdmin;
    StaderConfig staderConfig;
    StaderInsuranceFund iFund;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

        proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        StaderInsuranceFund iFundImpl = new StaderInsuranceFund();
        TransparentUpgradeableProxy iFundProxy = new TransparentUpgradeableProxy(
            address(iFundImpl),
            address(proxyAdmin),
            ''
        );
        iFund = StaderInsuranceFund(address(iFundProxy));
        iFund.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderInsuranceFund(address(iFund));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        StaderInsuranceFund iFundImpl = new StaderInsuranceFund();
        TransparentUpgradeableProxy iFundProxy = new TransparentUpgradeableProxy(
            address(iFundImpl),
            address(proxyAdmin),
            ''
        );
        StaderInsuranceFund iFund2 = StaderInsuranceFund(address(iFundProxy));
        iFund2.initialize(staderAdmin, address(staderConfig));
    }

    function test_initialize() public {
        assertEq(address(iFund.staderConfig()), address(staderConfig));
        assertTrue(iFund.hasRole(iFund.DEFAULT_ADMIN_ROLE(), staderAdmin));
        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }

    function test_depositFund(uint256 _ethAmount, address anyone) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin));

        hoax(address(anyone), _ethAmount); // provides anyone _ethAmount and makes it the caller for next call
        assertEq(address(iFund).balance, 0);
        iFund.depositFund{value: _ethAmount}();
        assertEq(address(iFund).balance, _ethAmount);
    }

    function test_withdaw(address anyone, uint256 amount) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        uint256 depositAmount = 5 ether;
        startHoax(anyone, depositAmount);

        iFund.depositFund{value: depositAmount}();
        assertEq(address(iFund).balance, depositAmount);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        iFund.withdrawFund(amount);
        vm.stopPrank();

        assertEq(staderManager.balance, 0);

        vm.startPrank(staderManager);

        if (amount > depositAmount || amount == 0) {
            vm.expectRevert(IStaderInsuranceFund.InvalidAmountProvided.selector);
            iFund.withdrawFund(amount);
            return;
        }

        iFund.withdrawFund(amount);
        vm.stopPrank();

        assertEq(staderManager.balance, amount);
        assertEq(address(iFund).balance, depositAmount - amount);
    }

    function test_reimburseUserFund(address anyone, uint256 amount) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin));

        uint256 depositAmount = 5 ether;
        startHoax(anyone, depositAmount);

        iFund.depositFund{value: depositAmount}();
        assertEq(address(iFund).balance, depositAmount);

        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        iFund.reimburseUserFund(amount);
        vm.stopPrank();

        PermissionedPoolMock permissionedPool = new PermissionedPoolMock(address(staderConfig));
        vm.prank(staderAdmin);
        staderConfig.updatePermissionedPool(address(permissionedPool));

        vm.prank(address(permissionedPool));

        if (amount > depositAmount) {
            vm.expectRevert(IStaderInsuranceFund.InSufficientBalance.selector);
            iFund.reimburseUserFund(amount);
            return;
        }

        assertEq(address(iFund).balance, depositAmount);
        assertEq(address(permissionedPool).balance, 0);
        iFund.reimburseUserFund(amount);

        assertEq(address(iFund).balance, depositAmount - amount);
        assertEq(address(permissionedPool).balance, amount);
    }

    function test_updateStaderConfig(address anyone) public {
        vm.assume(anyone != address(0) && anyone != staderAdmin);
        // not staderAdmin
        vm.prank(anyone);
        vm.expectRevert();
        iFund.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        iFund.updateStaderConfig(vm.addr(203));
        assertEq(address(iFund.staderConfig()), vm.addr(203));
    }
}
