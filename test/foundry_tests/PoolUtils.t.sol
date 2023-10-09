// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/PoolUtils.sol';

import '../mocks/NodeRegistryMock.sol';
import '../mocks/PoolMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PoolUtilsTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;

    PoolUtils poolUtils;
    StaderConfig staderConfig;

    PoolMock pool;
    NodeRegistryMock nodeRegistry;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        address ethDepositAddr = vm.addr(103);
        nodeRegistry = new NodeRegistryMock();
        pool = new PoolMock(address(nodeRegistry));

        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, address(ethDepositAddr));

        PoolUtils poolUtilsImpl = new PoolUtils();
        TransparentUpgradeableProxy poolUtilsProxy = new TransparentUpgradeableProxy(
            address(poolUtilsImpl),
            address(admin),
            ''
        );
        poolUtils = PoolUtils(payable(address(poolUtilsProxy)));
        poolUtils.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();

        PoolUtils poolUtilsImpl = new PoolUtils();
        TransparentUpgradeableProxy poolUtilsProxy = new TransparentUpgradeableProxy(
            address(poolUtilsImpl),
            address(admin),
            ''
        );
        poolUtils = PoolUtils(payable(address(poolUtilsProxy)));
        poolUtils.initialize(staderAdmin, address(staderConfig));
    }

    function test_poolUtilsInitialize() public {
        assertEq(address(poolUtils.staderConfig()), address(staderConfig));
        assertTrue(poolUtils.hasRole(poolUtils.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_addNewPool() public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        poolUtils.addNewPool(1, address(pool));

        vm.startPrank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.poolAddressById(1), address(pool));
        vm.expectRevert(IPoolUtils.ExistingOrMismatchingPoolId.selector);
        poolUtils.addNewPool(1, address(pool));
    }

    function test_updatePoolAddressFailCases() public {
        vm.mockCall(
            address(vm.addr(105)),
            abi.encodeWithSelector(IStaderPoolBase.getNodeRegistry.selector),
            abi.encode(vm.addr(106))
        );

        vm.mockCall(address(vm.addr(106)), abi.encodeWithSelector(INodeRegistry.POOL_ID.selector), abi.encode(2));
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));

        vm.startPrank(staderAdmin);
        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.updatePoolAddress(2, vm.addr(105));

        vm.expectRevert(UtilLib.ZeroAddress.selector);
        poolUtils.updatePoolAddress(1, address(0));

        vm.expectRevert(IPoolUtils.MismatchingPoolId.selector);
        poolUtils.updatePoolAddress(1, vm.addr(105));
        vm.stopPrank();
    }

    function test_updatePoolAddress() public {
        vm.mockCall(
            address(vm.addr(105)),
            abi.encodeWithSelector(IStaderPoolBase.getNodeRegistry.selector),
            abi.encode(vm.addr(106))
        );

        vm.mockCall(address(vm.addr(106)), abi.encodeWithSelector(INodeRegistry.POOL_ID.selector), abi.encode(1));
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        vm.prank(staderAdmin);
        poolUtils.updatePoolAddress(1, vm.addr(105));
        assertEq(poolUtils.poolAddressById(1), vm.addr(105));
    }

    function test_processValidatorExitList() public {
        bytes[] memory pubkey = new bytes[](2);
        pubkey[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkey[1] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

        vm.expectRevert(UtilLib.CallerNotOperator.selector);
        poolUtils.processValidatorExitList(pubkey);

        vm.prank(operator);
        poolUtils.processValidatorExitList(pubkey);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        poolUtils.updateStaderConfig(newStaderConfig);
        assertEq(address(poolUtils.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        poolUtils.updateStaderConfig(newStaderConfig);
        assertEq(address(poolUtils.staderConfig()), newStaderConfig);
    }

    function test_getCommissionFee() public {
        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getProtocolFee(1);

        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getOperatorFee(1);

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));

        assertEq(poolUtils.getProtocolFee(1), 500);
        assertEq(poolUtils.getOperatorFee(1), 500);
    }

    function test_ValidatorCounts() public {
        address permissionedPool = vm.addr(105);
        address permissionedNodeRegistry = vm.addr(106);
        vm.mockCall(
            address(permissionedPool),
            abi.encodeWithSelector(IStaderPoolBase.getNodeRegistry.selector),
            abi.encode(permissionedNodeRegistry)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(2)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.getTotalActiveValidatorCount.selector),
            abi.encode(5)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.getTotalQueuedValidatorCount.selector),
            abi.encode(5)
        );

        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getActiveValidatorCountByPool(1);
        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getQueuedValidatorCountByPool(1);
        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getActiveValidatorCountByPool(2);
        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getQueuedValidatorCountByPool(2);

        vm.startPrank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        poolUtils.addNewPool(2, permissionedPool);

        assertEq(poolUtils.getActiveValidatorCountByPool(1), 10);
        assertEq(poolUtils.getActiveValidatorCountByPool(2), 5);

        assertEq(poolUtils.getTotalActiveValidatorCount(), 15);
        assertEq(poolUtils.getQueuedValidatorCountByPool(1), 10);
        assertEq(poolUtils.getQueuedValidatorCountByPool(2), 5);
    }

    function test_getSocializingPoolAddress() public {
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IStaderPoolBase.getSocializingPoolAddress.selector),
            abi.encode(vm.addr(110))
        );

        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getSocializingPoolAddress(1);
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getSocializingPoolAddress(1), vm.addr(110));
    }

    function test_getOperatorTotalNonTerminalKeys() public {
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.getOperatorTotalNonTerminalKeys.selector),
            abi.encode(100)
        );

        vm.expectRevert(IPoolUtils.PoolIdNotPresent.selector);
        poolUtils.getOperatorTotalNonTerminalKeys(1, vm.addr(110), 0, 100);
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getOperatorTotalNonTerminalKeys(1, vm.addr(110), 0, 100), 100);
    }

    function test_getCollateralETH() public {
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getCollateralETH(1), 4 ether);
    }

    function test_getNodeRegistry() public {
        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getNodeRegistry(1), address(nodeRegistry));
    }

    function test_isExistingPubkey() public {
        bytes memory pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        assertFalse(poolUtils.isExistingPubkey(pubkey));

        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.isExistingPubkey.selector),
            abi.encode(true)
        );

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertTrue(poolUtils.isExistingPubkey(pubkey));
    }

    function test_isExistingOperator() public {
        assertFalse(poolUtils.isExistingOperator(vm.addr(110)));

        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.isExistingOperator.selector),
            abi.encode(true)
        );

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertTrue(poolUtils.isExistingOperator(vm.addr(110)));
    }

    function test_getOperatorPoolId() public {
        vm.expectRevert(IPoolUtils.OperatorIsNotOnboarded.selector);
        poolUtils.getOperatorPoolId(vm.addr(110));

        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.isExistingOperator.selector),
            abi.encode(true)
        );

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getOperatorPoolId(vm.addr(110)), 1);
    }

    function test_getValidatorPoolId() public {
        bytes memory pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        vm.expectRevert(IPoolUtils.PubkeyDoesNotExit.selector);
        poolUtils.getValidatorPoolId(pubkey);

        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.isExistingPubkey.selector),
            abi.encode(true)
        );

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        assertEq(poolUtils.getValidatorPoolId(pubkey), 1);
    }

    function test_getPoolIdArray() public {
        address permissionedPool = vm.addr(105);
        address permissionedNodeRegistry = vm.addr(106);
        vm.mockCall(
            address(permissionedPool),
            abi.encodeWithSelector(IStaderPoolBase.getNodeRegistry.selector),
            abi.encode(permissionedNodeRegistry)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(2)
        );

        vm.startPrank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        poolUtils.addNewPool(2, permissionedPool);

        uint8[] memory poolIDArray = poolUtils.getPoolIdArray();

        assertEq(poolIDArray[0], 1);
        assertEq(poolIDArray[1], 2);
        assertEq(poolIDArray.length, 2);
    }

    function test_onlyValidNameWithEmptyString(string calldata _name) public {
        vm.assume(bytes(_name).length == 0);
        vm.expectRevert(IPoolUtils.EmptyNameString.selector);
        poolUtils.onlyValidName(_name);
    }

    function test_onlyValidNameWithVeryLargeString(string calldata _name) public {
        vm.mockCall(
            address(staderConfig),
            abi.encodeWithSelector(IStaderConfig.getOperatorMaxNameLength.selector),
            abi.encode(5)
        );
        vm.assume(bytes(_name).length == 6);
        vm.expectRevert(IPoolUtils.NameCrossedMaxLength.selector);
        poolUtils.onlyValidName(_name);
    }

    function test_onlyValidKeys() public {
        bytes memory pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        bytes
            memory preDepositSig = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        bytes
            memory depositSig = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';

        bytes memory invalidPubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5';
        bytes
            memory invalidPreDepositSig = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad4';
        bytes
            memory invalidDepositSig = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489e';
        vm.expectRevert(IPoolUtils.InvalidLengthOfPubkey.selector);
        poolUtils.onlyValidKeys(invalidPubkey, preDepositSig, depositSig);

        vm.expectRevert(IPoolUtils.InvalidLengthOfSignature.selector);
        poolUtils.onlyValidKeys(pubkey, invalidPreDepositSig, depositSig);

        vm.expectRevert(IPoolUtils.InvalidLengthOfSignature.selector);
        poolUtils.onlyValidKeys(pubkey, preDepositSig, invalidDepositSig);

        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.isExistingPubkey.selector),
            abi.encode(true)
        );

        vm.prank(staderManager);
        poolUtils.addNewPool(1, address(pool));

        vm.expectRevert(IPoolUtils.PubkeyAlreadyExist.selector);
        poolUtils.onlyValidKeys(pubkey, preDepositSig, depositSig);
    }

    function test_calculateRewardShare() public {
        address permissionedPool = vm.addr(105);
        address permissionedNodeRegistry = vm.addr(106);
        vm.mockCall(
            address(permissionedPool),
            abi.encodeWithSelector(IStaderPoolBase.getNodeRegistry.selector),
            abi.encode(permissionedNodeRegistry)
        );
        vm.mockCall(
            address(permissionedPool),
            abi.encodeWithSelector(IStaderPoolBase.protocolFee.selector),
            abi.encode(500)
        );

        vm.mockCall(
            address(permissionedPool),
            abi.encodeWithSelector(IStaderPoolBase.operatorFee.selector),
            abi.encode(500)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.POOL_ID.selector),
            abi.encode(2)
        );

        vm.mockCall(
            address(permissionedNodeRegistry),
            abi.encodeWithSelector(INodeRegistry.getCollateralETH.selector),
            abi.encode(0)
        );

        vm.startPrank(staderManager);
        poolUtils.addNewPool(1, address(pool));
        poolUtils.addNewPool(2, permissionedPool);

        (uint256 userShareP1, uint256 operatorShareP1, uint256 protocolShareP1) = poolUtils.calculateRewardShare(
            1,
            1 ether
        );

        assertEq(userShareP1, 0.7875 ether);
        assertEq(operatorShareP1, 0.16875 ether);
        assertEq(protocolShareP1, 0.04375 ether);

        (uint256 userShareP2, uint256 operatorShareP2, uint256 protocolShareP2) = poolUtils.calculateRewardShare(
            2,
            1 ether
        );

        assertEq(userShareP2, 0.9 ether);
        assertEq(operatorShareP2, 0.05 ether);
        assertEq(protocolShareP2, 0.05 ether);
    }
}
