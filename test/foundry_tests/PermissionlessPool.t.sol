// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/factory/VaultFactory.sol';
import '../../contracts/PermissionlessPool.sol';

import '../mocks/ETHDepositMock.sol';
import '../mocks/StakePoolManagerMock.sol';
import '../mocks/PermissionlessNodeRegistryMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PermissionlessPoolTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;
    ETHDepositMock ethDepositAddr;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionlessPool permissionlessPool;

    StakePoolManagerMock poolManager;
    PermissionlessNodeRegistryMock nodeRegistry;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        ethDepositAddr = new ETHDepositMock();
        poolManager = new StakePoolManagerMock();
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

        PermissionlessPool permissionlessPoolImpl = new PermissionlessPool();
        TransparentUpgradeableProxy permissionlessPoolProxy = new TransparentUpgradeableProxy(
            address(permissionlessPoolImpl),
            address(admin),
            ''
        );
        nodeRegistry = new PermissionlessNodeRegistryMock();
        permissionlessPool = PermissionlessPool(payable(address(permissionlessPoolProxy)));
        permissionlessPool.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStakePoolManager(address(poolManager));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updatePermissionlessNodeRegistry(address(nodeRegistry));
        staderConfig.updatePermissionlessSocializingPool(vm.addr(105));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PermissionlessPool permissionlessPoolImpl = new PermissionlessPool();
        TransparentUpgradeableProxy permissionlessPoolProxy = new TransparentUpgradeableProxy(
            address(permissionlessPoolImpl),
            address(admin),
            ''
        );
        permissionlessPool = PermissionlessPool(payable(address(permissionlessPoolProxy)));
        permissionlessPool.initialize(staderAdmin, address(staderConfig));
    }

    function test_permissionlessPoolInitialize() public {
        assertEq(address(permissionlessPool.staderConfig()), address(staderConfig));
        assertEq(permissionlessPool.protocolFee(), 500);
        assertEq(permissionlessPool.operatorFee(), 500);
        assertEq(permissionlessPool.MAX_COMMISSION_LIMIT_BIPS(), 1500);
        assertEq(permissionlessPool.DEPOSIT_NODE_BOND(), 3 ether);
        assertTrue(permissionlessPool.hasRole(permissionlessPool.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_ReceiveFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        payable(permissionlessPool).send(1 ether);
        vm.stopPrank();
    }

    function test_FallbackFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        payable(permissionlessPool).call{value: 1 ether}('abi.encodeWithSignature("nonExistentFunction()")');
        vm.stopPrank();
    }

    function test_receiveRemainingCollateralETH(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(this), _amount);
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        permissionlessPool.receiveRemainingCollateralETH{value: _amount}();
        vm.deal(address(nodeRegistry), _amount);
        vm.prank(address(nodeRegistry));
        permissionlessPool.receiveRemainingCollateralETH{value: _amount}();
        assertEq(address(permissionlessPool).balance, _amount);
    }

    function test_preDepositOnBeaconChain() public {
        bytes[] memory pubkey = new bytes[](2);
        pubkey[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkey[1] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

        bytes[] memory preDepositSig = new bytes[](2);
        preDepositSig[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        preDepositSig[
            1
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';

        startHoax(address(nodeRegistry), 2 ether);
        permissionlessPool.preDepositOnBeaconChain{value: 2 ether}(pubkey, preDepositSig, 1, 2);
    }

    function testFail_preDepositOnBeaconChain() public {
        bytes[] memory pubkey = new bytes[](3);
        pubkey[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkey[1] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkey[2] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

        bytes[] memory preDepositSig = new bytes[](3);
        preDepositSig[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        preDepositSig[
            1
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        preDepositSig[
            2
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';

        startHoax(address(nodeRegistry), 3 ether);
        permissionlessPool.preDepositOnBeaconChain{value: 2 ether}(pubkey, preDepositSig, 1, 2);
    }

    function test_preDepositOnBeaconChainWithExtraETH() public {
        bytes[] memory pubkey = new bytes[](2);
        pubkey[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkey[1] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

        bytes[] memory preDepositSig = new bytes[](2);
        preDepositSig[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        preDepositSig[
            1
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';

        startHoax(address(nodeRegistry), 10 ether);
        permissionlessPool.preDepositOnBeaconChain{value: 5 ether}(pubkey, preDepositSig, 1, 2);
        assertEq(address(permissionlessPool).balance, 3 ether);
    }

    function test_StakeUserETHToBeaconChain() public {
        startHoax(address(poolManager));
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
        vm.deal(address(nodeRegistry), 50 ether);
        permissionlessPool.stakeUserETHToBeaconChain{value: 112 ether}();
        assertEq(address(permissionlessPool).balance, 0);
        assertEq(address(nodeRegistry).balance, 38 ether);
        assertEq(address(ethDepositAddr).balance, 124 ether);
    }

    function test_getTotalQueuedValidatorCount() public {
        assertEq(permissionlessPool.getTotalQueuedValidatorCount(), 5);
    }

    function test_getTotalActiveValidatorCount() public {
        assertEq(permissionlessPool.getTotalActiveValidatorCount(), 5);
    }

    function test_getOperatorTotalNonTerminalKeys() public {
        assertEq(permissionlessPool.getOperatorTotalNonTerminalKeys(address(this), 0, 100), 5);
    }

    function test_getSocializingPoolAddress() public {
        assertEq(permissionlessPool.getSocializingPoolAddress(), vm.addr(105));
    }

    function test_getCollateralETH() public {
        assertEq(permissionlessPool.getCollateralETH(), 4 ether);
    }

    function test_getNodeRegistry() public {
        assertEq(permissionlessPool.getNodeRegistry(), address(nodeRegistry));
    }

    function test_isExistingPubkey() public {
        bytes memory pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        assertEq(permissionlessPool.isExistingPubkey(pubkey), true);
    }

    function test_isExistingOperatory() public {
        assertEq(permissionlessPool.isExistingOperator(address(this)), true);
    }

    function test_setCommissionFees(uint64 protocolFee, uint64 operatorFee) public {
        vm.assume(protocolFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(operatorFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(protocolFee + operatorFee <= permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.prank(staderManager);
        permissionlessPool.setCommissionFees(protocolFee, operatorFee);
        assertEq(permissionlessPool.protocolFee(), protocolFee);
        assertEq(permissionlessPool.operatorFee(), operatorFee);
    }

    function test_test_setCommissionFeesWithInvalidInput(uint64 protocolFee, uint64 operatorFee) public {
        vm.assume(protocolFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(operatorFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(protocolFee + operatorFee > permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.expectRevert(IStaderPoolBase.InvalidCommission.selector);
        vm.prank(staderManager);
        permissionlessPool.setCommissionFees(protocolFee, operatorFee);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        permissionlessPool.updateStaderConfig(newStaderConfig);
        assertEq(address(permissionlessPool.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        permissionlessPool.updateStaderConfig(newStaderConfig);
        assertEq(address(permissionlessPool.staderConfig()), newStaderConfig);
    }
}
