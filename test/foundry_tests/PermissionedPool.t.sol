pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/factory/VaultFactory.sol';
import '../../contracts/PermissionedPool.sol';

import '../mocks/ETHDepositMock.sol';
import '../mocks/StaderInsuranceFundMock.sol';
import '../mocks/StakePoolManagerMock.sol';
import '../mocks/PermissionedNodeRegistryMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PermissionedPoolTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;
    ETHDepositMock ethDepositAddr;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionedPool permissionedPool;

    StakePoolManagerMock poolManager;
    StaderInsuranceFundMock insuranceFund;
    PermissionedNodeRegistryMock nodeRegistry;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        ethDepositAddr = new ETHDepositMock();
        poolManager = new StakePoolManagerMock();
        insuranceFund = new StaderInsuranceFundMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, address(ethDepositAddr));

        VaultFactory vaultImp = new VaultFactory();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vaultImp), address(admin), '');

        vaultFactory = VaultFactory(address(vaultProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        PermissionedPool permissionedPoolImpl = new PermissionedPool();
        TransparentUpgradeableProxy permissionedPoolProxy = new TransparentUpgradeableProxy(
            address(permissionedPoolImpl),
            address(admin),
            ''
        );
        nodeRegistry = new PermissionedNodeRegistryMock();
        permissionedPool = PermissionedPool(payable(address(permissionedPoolProxy)));
        permissionedPool.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStakePoolManager(address(poolManager));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updateStaderInsuranceFund(address(insuranceFund));
        staderConfig.updatePermissionedNodeRegistry(address(nodeRegistry));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PermissionedPool permissionedPoolImpl = new PermissionedPool();
        TransparentUpgradeableProxy permissionedPoolProxy = new TransparentUpgradeableProxy(
            address(permissionedPoolImpl),
            address(admin),
            ''
        );
        permissionedPool = PermissionedPool(payable(address(permissionedPoolProxy)));
        permissionedPool.initialize(staderAdmin, address(staderConfig));
    }

    function test_PermissionedPoolInitialize() public {
        assertEq(address(permissionedPool.staderConfig()), address(staderConfig));
        assertEq(permissionedPool.protocolFee(), 500);
        assertEq(permissionedPool.operatorFee(), 500);
        assertEq(permissionedPool.MAX_COMMISSION_LIMIT_BIPS(), 1500);
        assertTrue(permissionedPool.hasRole(permissionedPool.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_ReceiveFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        payable(permissionedPool).send(1 ether);
        vm.stopPrank();
    }

    function test_FallbackFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        (bool success, ) = payable(permissionedPool).call{value: 1 ether}(
            'abi.encodeWithSignature("nonExistentFunction()")'
        );
        vm.stopPrank();
    }

    function test_ReceiveInsuranceFund(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(this), _amount);
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        permissionedPool.receiveInsuranceFund{value: _amount}();
        vm.deal(address(insuranceFund), _amount);
        vm.prank(address(insuranceFund));
        permissionedPool.receiveInsuranceFund{value: _amount}();
        assertEq(address(permissionedPool).balance, _amount);
    }

    function test_StakeUserETHToBeaconChain() public {
        startHoax(address(poolManager), 70 ether);
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.validatorRegistry.selector),
            abi.encode(
                ValidatorStatus.INITIALIZED,
                '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336751',
                '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6',
                '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6',
                address(this),
                1,
                150,
                150
            )
        );
        permissionedPool.stakeUserETHToBeaconChain{value: 64 ether}();
        assertEq(address(permissionedPool).balance, 62 ether);
        assertEq(address(ethDepositAddr).balance, 2 ether);
        assertEq(permissionedPool.preDepositValidatorCount(), 2);
    }
}