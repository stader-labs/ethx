pragma solidity ^0.8.10;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderOracle.sol';
import '../../contracts/SocializingPool.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderOracleTest is Test {
    address staderAdmin;
    address staderManager;

    StaderOracle staderOracle;
    SocializingPool permissionedSP;
    SocializingPool permissionlessSP;

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

        StaderOracle oracleImpl = new StaderOracle();
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(admin),
            ''
        );
        staderOracle = StaderOracle(address(oracleProxy));
        staderOracle.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        permissionedSP = SocializingPool(payable(permissionedSPProxy));
        permissionedSP.initialize(staderAdmin, address(staderConfig));

        TransparentUpgradeableProxy permissionlessSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        permissionlessSP = SocializingPool(payable(permissionlessSPProxy));
        permissionlessSP.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updatePermissionedSocializingPool(address(permissionedSP));
        staderConfig.updatePermissionlessSocializingPool(address(permissionlessSP));
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();
    }

    function test_justToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        StaderOracle oracleImpl = new StaderOracle();
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(admin),
            ''
        );
        StaderOracle staderOracle2 = StaderOracle(address(oracleProxy));
        staderOracle2.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        SocializingPool permissionedSP2 = SocializingPool(payable(permissionedSPProxy));
        permissionedSP2.initialize(staderAdmin, address(staderConfig));
    }

    function test_initialize() public {
        assertEq(address(permissionedSP.staderConfig()), address(staderConfig));
        assertEq(address(permissionlessSP.staderConfig()), address(staderConfig));
        assertEq(address(staderOracle.staderConfig()), address(staderConfig));

        assertTrue(permissionedSP.hasRole(permissionedSP.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertTrue(permissionlessSP.hasRole(permissionlessSP.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertTrue(staderOracle.hasRole(staderOracle.DEFAULT_ADMIN_ROLE(), staderAdmin));

        assertEq(permissionedSP.initialBlock(), block.number);
        assertEq(permissionlessSP.initialBlock(), block.number);

        assertEq(staderConfig.getStaderOracle(), address(staderOracle));
        assertEq(staderConfig.getPermissionedSocializingPool(), address(permissionedSP));
        assertEq(staderConfig.getPermissionlessSocializingPool(), address(permissionlessSP));
        assertEq(staderConfig.getStaderToken(), address(staderToken));

        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }
}
