// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/factory/VaultFactory.sol';
import '../../contracts/NodeELRewardVault.sol';
import '../../contracts/PermissionedNodeRegistry.sol';

import '../mocks/PenaltyMock.sol';
import '../mocks/SocializingPoolMock.sol';
import '../mocks/SDCollateralMock.sol';
import '../mocks/StaderOracleMock.sol';
import '../mocks/PermissionedPoolMock.sol';
import '../mocks/StaderInsuranceFundMock.sol';
import '../mocks/StakePoolManagerMock.sol';
import '../mocks/OperatorRewardsCollectorMock.sol';
import '../mocks/PoolUtilsMockForDepositFlow.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PermissionedNodeRegistryTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;
    address permissionedNO;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionedNodeRegistry nodeRegistry;
    PoolUtilsMockForDepositFlow poolUtils;

    SocializingPoolMock socializingPoolMock;
    StaderOracleMock staderOracle;
    SDCollateralMock sdCollateral;
    PermissionedPoolMock permissionedPool;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);
        address ethDepositAddr = vm.addr(103);
        permissionedNO = vm.addr(104);

        PenaltyMock penalty = new PenaltyMock();
        socializingPoolMock = new SocializingPoolMock();
        staderOracle = new StaderOracleMock();
        sdCollateral = new SDCollateralMock();
        NodeELRewardVault nodeELImpl = new NodeELRewardVault();
        StakePoolManagerMock poolManager = new StakePoolManagerMock();
        StaderInsuranceFundMock insuranceFund = new StaderInsuranceFundMock();
        OperatorRewardsCollectorMock rewardCollector = new OperatorRewardsCollectorMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        VaultFactory vaultImp = new VaultFactory();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vaultImp), address(admin), '');

        vaultFactory = VaultFactory(address(vaultProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        PermissionedNodeRegistry nodeRegistryImpl = new PermissionedNodeRegistry();
        TransparentUpgradeableProxy nodeRegistryProxy = new TransparentUpgradeableProxy(
            address(nodeRegistryImpl),
            address(admin),
            ''
        );
        permissionedPool = new PermissionedPoolMock(address(staderConfig));
        nodeRegistry = PermissionedNodeRegistry(address(nodeRegistryProxy));
        nodeRegistry.initialize(staderAdmin, address(staderConfig));
        poolUtils = new PoolUtilsMockForDepositFlow(address(nodeRegistry), address(staderConfig));
        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updatePenaltyContract(address(penalty));
        staderConfig.updateStakePoolManager(address(poolManager));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updateStaderInsuranceFund(address(insuranceFund));
        staderConfig.updatePermissionedPool(address(permissionedPool));
        staderConfig.updateOperatorRewardsCollector(address(rewardCollector));
        staderConfig.updateNodeELRewardImplementation(address(nodeELImpl));
        staderConfig.updatePermissionedSocializingPool(address(socializingPoolMock));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vaultFactory.grantRole(vaultFactory.NODE_REGISTRY_CONTRACT(), address(nodeRegistry));
        vm.stopPrank();
        vm.prank(staderManager);
        address[] memory whitelistedNO = new address[](1);
        whitelistedNO[0] = permissionedNO;
        nodeRegistry.whitelistPermissionedNOs(whitelistedNO);
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PermissionedNodeRegistry nodeRegistryImpl = new PermissionedNodeRegistry();
        TransparentUpgradeableProxy nodeRegistryProxy = new TransparentUpgradeableProxy(
            address(nodeRegistryImpl),
            address(admin),
            ''
        );
        nodeRegistry = PermissionedNodeRegistry(address(nodeRegistryProxy));
        nodeRegistry.initialize(staderAdmin, address(staderConfig));
    }

    function test_PermissionedNodeRegistryInitialize() public {
        assertEq(address(nodeRegistry.staderConfig()), address(staderConfig));
        assertEq(nodeRegistry.nextValidatorId(), 1);
        assertEq(nodeRegistry.nextOperatorId(), 1);
        assertEq(nodeRegistry.inputKeyCountLimit(), 50);
        assertEq(nodeRegistry.maxNonTerminalKeyPerOperator(), 50);
        assertEq(nodeRegistry.verifiedKeyBatchSize(), 50);
        assertTrue(nodeRegistry.hasRole(nodeRegistry.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_OnboardOperator(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        assertFalse(nodeRegistry.isExistingOperator(operatorAddr));
        vm.expectRevert(IPermissionedNodeRegistry.NotAPermissionedNodeOperator.selector);
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        whitelistOperator(operatorAddr);
        vm.prank(operator);
        nodeRegistry.updateMaxOperatorId(0);
        vm.prank(operatorAddr);
        vm.expectRevert(IPermissionedNodeRegistry.MaxOperatorLimitReached.selector);
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        vm.prank(operator);
        nodeRegistry.updateMaxOperatorId(10);
        vm.startPrank(operatorAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.poolAddressById.selector),
            abi.encode(address(0))
        );
        vm.expectRevert(INodeRegistry.DuplicatePoolIDOrPoolNotAdded.selector);
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.poolAddressById.selector),
            abi.encode(address(permissionedPool))
        );
        address output = nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        assertEq(output, address(socializingPoolMock));
        assertTrue(nodeRegistry.isExistingOperator(operatorAddr));
        assertEq(nodeRegistry.getOperatorRewardAddress(operatorId), opRewardAddr);
        assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        assertEq(nodeRegistry.getSocializingPoolStateChangeBlock(operatorId), block.number);
        vm.stopPrank();
    }

    function test_OnboardExistingOperator(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.isExistingOperator.selector),
            abi.encode(true)
        );
        vm.expectRevert(INodeRegistry.OperatorAlreadyOnBoardedInProtocol.selector);
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        vm.stopPrank();
    }

    function test_OnboardOperatorWhenPaused(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        vm.prank(staderManager);
        nodeRegistry.pause();
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        vm.expectRevert('Pausable: paused');
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);
        vm.stopPrank();
        vm.prank(staderManager);
        nodeRegistry.unpause();
    }

    function test_addValidatorKeys() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        uint256 nextValidatorId = nodeRegistry.nextValidatorId();
        assertEq(nextValidatorId, 4);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[0]), 1);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[2]), 3);
        assertEq(nodeRegistry.isExistingPubkey(pubkeys[0]), true);
    }

    function test_addValidatorKeysWithMisMatchingInputs() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory preDepositSignature = new bytes[](1);
        bytes[] memory depositSignature = new bytes[](0);
        pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        preDepositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        vm.expectRevert(INodeRegistry.MisMatchingInputKeysSize.selector);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithInvalidKeyCount() public {
        bytes[] memory pubkeys = new bytes[](0);
        bytes[] memory preDepositSignature = new bytes[](0);
        bytes[] memory depositSignature = new bytes[](0);
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        vm.expectRevert(INodeRegistry.InvalidKeyCount.selector);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysOPCrossingMaxNonTerminalKeys() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        vm.prank(staderManager);
        nodeRegistry.updateMaxNonTerminalKeyPerOperator(2);
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        vm.expectRevert(INodeRegistry.maxKeyLimitReached.selector);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithInsufficientSDCollateral() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.hasEnoughSDCollateral.selector),
            abi.encode(false)
        );
        vm.expectRevert(INodeRegistry.NotEnoughSDCollateral.selector);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_markReadyToDepositValidator() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.prank(operator);
        nodeRegistry.updateVerifiedKeysBatchSize(2);
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), pubkeys.length);
        vm.startPrank(address(permissionedPool));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(permissionedNO);
        uint256 nextQueuedValidatorIndexBefore = nodeRegistry.nextQueuedValidatorIndexByOperatorId(operatorId);
        assertEq(nextQueuedValidatorIndexBefore, 0);
        vm.expectRevert(INodeRegistry.UNEXPECTED_STATUS.selector);
        nodeRegistry.onlyPreDepositValidator(pubkeys[0]);
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys[0]);
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys[1]);
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys[2]);
        nodeRegistry.onlyPreDepositValidator(pubkeys[0]);
        nodeRegistry.updateQueuedValidatorIndex(operatorId, nextQueuedValidatorIndexBefore + 3);
        nodeRegistry.increaseTotalActiveValidatorCount(3);

        bytes[] memory readyToDepositKeys = new bytes[](1);
        bytes[] memory frontRunKeys = new bytes[](1);
        bytes[] memory invalidSigKeys = new bytes[](1);
        readyToDepositKeys[0] = pubkeys[0];
        frontRunKeys[0] = pubkeys[1];
        invalidSigKeys[0] = pubkeys[2];
        uint256 readyToDepositValidatorId = nodeRegistry.validatorIdByPubkey(readyToDepositKeys[0]);
        uint256 frontRunValidatorId = nodeRegistry.validatorIdByPubkey(frontRunKeys[0]);
        uint256 invalidSigValidatorId = nodeRegistry.validatorIdByPubkey(invalidSigKeys[0]);
        vm.prank(address(staderOracle));
        vm.expectRevert(INodeRegistry.TooManyVerifiedKeysReported.selector);
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        vm.prank(operator);
        nodeRegistry.updateVerifiedKeysBatchSize(50);
        vm.startPrank(address(staderOracle));
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        vm.expectRevert(INodeRegistry.UNEXPECTED_STATUS.selector);
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        (ValidatorStatus readyToDepositStatus, , , , , , , ) = nodeRegistry.validatorRegistry(
            readyToDepositValidatorId
        );
        (ValidatorStatus frontRunStatus, , , , , , , ) = nodeRegistry.validatorRegistry(frontRunValidatorId);
        (ValidatorStatus invalidSigStatus, , , , , , , ) = nodeRegistry.validatorRegistry(invalidSigValidatorId);
        require(readyToDepositStatus == ValidatorStatus.PRE_DEPOSIT);
        require(frontRunStatus == ValidatorStatus.FRONT_RUN);
        require(invalidSigStatus == ValidatorStatus.INVALID_SIGNATURE);
        vm.stopPrank();
        assertEq(nodeRegistry.totalActiveValidatorCount(), 1);
        vm.prank(permissionedNO);
        vm.expectRevert(INodeRegistry.OperatorIsDeactivate.selector);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
    }

    function test_withdrawnValidators() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.prank(operator);
        staderConfig.updateWithdrawnKeysBatchSize(1);
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        uint256 validatorId2 = nodeRegistry.validatorIdByPubkey(pubkeys[1]);
        uint256 validatorId3 = nodeRegistry.validatorIdByPubkey(pubkeys[2]);

        vm.startPrank(address(permissionedPool));
        nodeRegistry.updateDepositStatusAndBlock(validatorId1);
        nodeRegistry.updateDepositStatusAndBlock(validatorId2);
        nodeRegistry.updateDepositStatusAndBlock(validatorId3);
        nodeRegistry.increaseTotalActiveValidatorCount(3);
        vm.stopPrank();
        vm.prank(address(staderOracle));
        vm.expectRevert(INodeRegistry.TooManyWithdrawnKeysReported.selector);
        nodeRegistry.withdrawnValidators(pubkeys);
        vm.prank(operator);
        staderConfig.updateWithdrawnKeysBatchSize(100);
        vm.startPrank(address(staderOracle));
        nodeRegistry.withdrawnValidators(pubkeys);
        vm.expectRevert(INodeRegistry.UNEXPECTED_STATUS.selector);
        nodeRegistry.withdrawnValidators(pubkeys);
        assertEq(nodeRegistry.getTotalActiveValidatorCount(), 0);
        vm.stopPrank();
    }

    function test_updateNextQueuedValidatorIndex(uint64 __opAddrSeed, uint256 _nextQueuedValidatorIndex) public {
        vm.assume(_nextQueuedValidatorIndex > 0);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        whitelistOperator(operatorAddr);
        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP', payable(operatorAddr));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        vm.startPrank(address(permissionedPool));
        nodeRegistry.updateQueuedValidatorIndex(operatorId, _nextQueuedValidatorIndex);
        uint256 nextQueuedValidatorIndex = nodeRegistry.nextQueuedValidatorIndexByOperatorId(operatorId);
        assertEq(nextQueuedValidatorIndex, _nextQueuedValidatorIndex);
    }

    function test_updateInputKeyCountLimit(uint16 _keyCountLimit) public {
        vm.prank(operator);
        nodeRegistry.updateInputKeyCountLimit(_keyCountLimit);
        assertEq(nodeRegistry.inputKeyCountLimit(), _keyCountLimit);
    }

    function testFail_updateInputKeyCountLimit(uint16 _keyCountLimit) public {
        nodeRegistry.updateInputKeyCountLimit(_keyCountLimit);
        assertEq(nodeRegistry.inputKeyCountLimit(), _keyCountLimit);
    }

    function test_updateMaxNonTerminalKeyPerOperator(uint64 _maxNonTerminalKeyPerOperator) public {
        vm.prank(staderManager);
        nodeRegistry.updateMaxNonTerminalKeyPerOperator(_maxNonTerminalKeyPerOperator);
        assertEq(nodeRegistry.maxNonTerminalKeyPerOperator(), _maxNonTerminalKeyPerOperator);
    }

    function testFail_updateMaxNonTerminalKeyPerOperator(uint64 _maxNonTerminalKeyPerOperator) public {
        nodeRegistry.updateMaxNonTerminalKeyPerOperator(_maxNonTerminalKeyPerOperator);
        assertEq(nodeRegistry.maxNonTerminalKeyPerOperator(), _maxNonTerminalKeyPerOperator);
    }

    function test_updateVerifiedKeysBatchSize(uint256 _verifiedKeysBatchSize) public {
        vm.prank(operator);
        nodeRegistry.updateVerifiedKeysBatchSize(_verifiedKeysBatchSize);
        assertEq(nodeRegistry.verifiedKeyBatchSize(), _verifiedKeysBatchSize);
    }

    function testFail_updateVerifiedKeysBatchSize(uint256 _verifiedKeysBatchSize) public {
        nodeRegistry.updateVerifiedKeysBatchSize(_verifiedKeysBatchSize);
        assertEq(nodeRegistry.verifiedKeyBatchSize(), _verifiedKeysBatchSize);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.prank(staderAdmin);
        nodeRegistry.updateStaderConfig(newStaderConfig);
        assertEq(address(nodeRegistry.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfigWithoutAdminRole(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        nodeRegistry.updateStaderConfig(newStaderConfig);
        assertEq(address(nodeRegistry.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfigWithZeroAddr() public {
        address newStaderConfig = vm.addr(0);
        vm.prank(staderAdmin);
        nodeRegistry.updateStaderConfig(newStaderConfig);
        assertEq(address(nodeRegistry.staderConfig()), newStaderConfig);
    }

    function test_updateOperatorRewardAddress(string calldata _operatorName, uint64 __opAddrSeed) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(456));
        address payable newOPRewardAddr = payable(vm.addr(567));
        whitelistOperator(operatorAddr);

        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator(_operatorName, opRewardAddr);

        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        string memory newOpName = string(abi.encodePacked(_operatorName, 'test'));

        // propose new reward addr
        vm.expectRevert(INodeRegistry.CallerNotExistingRewardAddress.selector);
        vm.prank(operatorAddr);
        nodeRegistry.initiateRewardAddressChange(operatorAddr, newOPRewardAddr);

        // passed wrong new reward address by mistake
        vm.prank(opRewardAddr);
        nodeRegistry.initiateRewardAddressChange(operatorAddr, vm.addr(666));

        vm.prank(opRewardAddr);
        nodeRegistry.initiateRewardAddressChange(operatorAddr, newOPRewardAddr);

        address pendingRewardAddress = nodeRegistry.proposedRewardAddressByOperatorId(operatorId);
        assertEq(pendingRewardAddress, newOPRewardAddr);

        // confirm new reward address
        vm.expectRevert(INodeRegistry.CallerNotNewRewardAddress.selector);
        vm.prank(opRewardAddr);
        nodeRegistry.confirmRewardAddressChange(operatorAddr);

        vm.expectRevert(INodeRegistry.CallerNotNewRewardAddress.selector);
        vm.prank(operatorAddr);
        nodeRegistry.confirmRewardAddressChange(operatorAddr);

        vm.prank(newOPRewardAddr);
        nodeRegistry.confirmRewardAddressChange(operatorAddr);

        (, , , address payable operatorRewardAddress, ) = nodeRegistry.operatorStructById(operatorId);
        assertEq(operatorRewardAddress, newOPRewardAddr);
    }

    function test_updateOperatorRewardAddressWithInvalidOperatorAddress() public {
        address operatorAddr = vm.addr(778);
        address payable opRewardAddr = payable(vm.addr(456));
        address payable newOPRewardAddr = payable(vm.addr(567));

        vm.expectRevert(INodeRegistry.CallerNotExistingRewardAddress.selector);
        vm.prank(opRewardAddr);
        nodeRegistry.initiateRewardAddressChange(operatorAddr, newOPRewardAddr);

        // it will pass if caller is address(0), which is not possible
        vm.prank(address(0));
        nodeRegistry.initiateRewardAddressChange(operatorAddr, newOPRewardAddr);
    }

    function test_updateOperatorRewardAddressWithZeroRewardAddr(string calldata _operatorName, uint64 __opAddrSeed)
        public
    {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        whitelistOperator(operatorAddr);
        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator(_operatorName, payable(operatorAddr));

        vm.expectRevert(UtilLib.ZeroAddress.selector);
        vm.prank(operatorAddr);
        nodeRegistry.initiateRewardAddressChange(operatorAddr, payable(address(0)));
    }

    function test_updateOperatorName(string calldata _operatorName, uint64 __opAddrSeed) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(_operatorName, payable(operatorAddr));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        string memory newOpName = string(abi.encodePacked(_operatorName, 'test'));
        nodeRegistry.updateOperatorName(newOpName);
        (, , string memory operatorName, , ) = nodeRegistry.operatorStructById(operatorId);
        assertEq(operatorName, newOpName);
        vm.stopPrank();
    }

    function test_updateOperatorNameWithInActiveOperator(string calldata _operatorName) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        string memory newOpName = string(abi.encodePacked(_operatorName, 'test'));
        vm.expectRevert(INodeRegistry.OperatorNotOnBoarded.selector);
        nodeRegistry.updateOperatorName(newOpName);
    }

    function test_updateOperatorNameWithInvalidName(string calldata _operatorName, uint64 __opAddrSeed) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(_operatorName, payable(operatorAddr));
        string memory newOpName = string(abi.encodePacked(''));
        vm.expectRevert(PoolUtilsMockForDepositFlow.EmptyNameString.selector);
        nodeRegistry.updateOperatorName(newOpName);
    }

    function test_increaseTotalActiveValidatorCount(uint256 _count) public {
        uint256 totalActiveValidatorsBefore = nodeRegistry.totalActiveValidatorCount();
        vm.prank(address(permissionedPool));
        nodeRegistry.increaseTotalActiveValidatorCount(_count);
        uint256 totalActiveValidatorsAfter = nodeRegistry.totalActiveValidatorCount();
        assertEq(totalActiveValidatorsAfter - totalActiveValidatorsBefore, _count);
    }

    function test_increaseTotalActiveValidatorCountCallerNotPermissionedPool(uint256 _count) public {
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        nodeRegistry.increaseTotalActiveValidatorCount(_count);
    }

    function test_getOperatorTotalNonTerminalKeys(
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed,
        uint256 _startIndex,
        uint256 _endIndex
    ) public {
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        vm.assume(_endIndex >= _startIndex);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP', opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        uint256 nonTerminalKeys = nodeRegistry.getOperatorTotalNonTerminalKeys(operatorAddr, _startIndex, _endIndex);
        uint256 validatorCount = nodeRegistry.getOperatorTotalKeys(operatorId);
        uint256 expectedNonTerminalKeys = _startIndex >= pubkeys.length
            ? 0
            : Math.min(_endIndex - _startIndex, validatorCount - _startIndex);
        assertEq(nonTerminalKeys, expectedNonTerminalKeys);
        assertEq(nodeRegistry.getOperatorTotalKeys(operatorId), pubkeys.length);
    }

    function test_getOperatorTotalNonTerminalKeysInvalidPagination(
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed,
        uint256 _startIndex,
        uint256 _endIndex
    ) public {
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        vm.assume(_startIndex > _endIndex);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        whitelistOperator(operatorAddr);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP', opRewardAddr);
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.expectRevert(INodeRegistry.InvalidStartAndEndIndex.selector);
        nodeRegistry.getOperatorTotalNonTerminalKeys(operatorAddr, _startIndex, _endIndex);
    }

    function test_getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize) public {
        vm.assume(_pageNumber > 0 && _pageNumber < 1000);
        vm.assume(_pageSize < 10000);
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), pubkeys.length);
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        uint256 validatorId2 = nodeRegistry.validatorIdByPubkey(pubkeys[1]);
        uint256 validatorId3 = nodeRegistry.validatorIdByPubkey(pubkeys[2]);
        vm.startPrank(address(permissionedPool));
        nodeRegistry.updateDepositStatusAndBlock(validatorId1);
        nodeRegistry.updateDepositStatusAndBlock(validatorId2);
        nodeRegistry.updateDepositStatusAndBlock(validatorId3);
        nodeRegistry.increaseTotalActiveValidatorCount(3);
        vm.stopPrank();
        Validator[] memory activeValidator = nodeRegistry.getAllActiveValidators(_pageNumber, _pageSize);
        uint256 startIndex = (_pageNumber - 1) * _pageSize + 1;
        uint256 nextValidatorId = nodeRegistry.nextValidatorId();
        uint256 expectedActiveValidatorCount = startIndex >= nextValidatorId
            ? 0
            : Math.min(_pageSize, nextValidatorId - startIndex);
        assertEq(activeValidator.length, expectedActiveValidatorCount);
    }

    function test_getAllActiveValidatorsWithZeroPageNumber(uint256 _pageSize) public {
        uint256 pageNumber = 0;
        vm.assume(_pageSize < 10000);
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), pubkeys.length);
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        vm.startPrank(address(permissionedPool));
        nodeRegistry.updateDepositStatusAndBlock(validatorId1);
        nodeRegistry.increaseTotalActiveValidatorCount(1);
        vm.stopPrank();
        vm.expectRevert(INodeRegistry.PageNumberIsZero.selector);
        nodeRegistry.getAllActiveValidators(pageNumber, _pageSize);
    }

    function test_getValidatorsByOperator() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP', payable(permissionedNO));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        Validator[] memory validators = nodeRegistry.getValidatorsByOperator(permissionedNO, 1, 100);
        assertEq(validators.length, 3);
        // assertEq(validators[0].pubkey, pubkeys[0]);
    }

    function test_getValidatorsByOperatorWithOperatorNotOnboarded(uint256 _pageNumber, uint256 _pageSize) public {
        vm.assume(_pageNumber > 0 && _pageNumber < 1000);
        vm.assume(_pageSize < 10000);
        address op = vm.addr(445);
        vm.expectRevert(INodeRegistry.OperatorNotOnBoarded.selector);
        nodeRegistry.getValidatorsByOperator(op, _pageNumber, _pageSize);
    }

    function test_getValidatorsByOperatorWithPageNumberZero(uint256 _pageSize) public {
        uint256 pageNumber = 0;
        address op = vm.addr(445);
        vm.expectRevert(INodeRegistry.PageNumberIsZero.selector);
        nodeRegistry.getValidatorsByOperator(op, pageNumber, _pageSize);
    }

    function test_AllocateValidatorsAndUpdateOperatorId() public {
        address operatorAddr = vm.addr(999);
        whitelistOperator(operatorAddr);
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        (
            bytes[] memory pubkeys1,
            bytes[] memory preDepositSignature1,
            bytes[] memory depositSignature1
        ) = getDifferentSetOfValidatorKeys();

        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP1', payable(operatorAddr));
        nodeRegistry.addValidatorKeys(pubkeys, preDepositSignature, depositSignature);
        uint256 operatorId1 = nodeRegistry.operatorIDByAddress(operatorAddr);
        vm.stopPrank();
        vm.startPrank(permissionedNO);
        nodeRegistry.onboardNodeOperator('testOP2', payable(permissionedNO));
        nodeRegistry.addValidatorKeys(pubkeys1, preDepositSignature1, depositSignature1);
        uint256 operatorId2 = nodeRegistry.operatorIDByAddress(permissionedNO);
        vm.stopPrank();
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), pubkeys.length + pubkeys1.length);
        assertEq(nodeRegistry.operatorIdForExcessDeposit(), operatorId1);
        vm.prank(address(permissionedPool));
        uint256[] memory selectedOperatorCapacity = nodeRegistry.allocateValidatorsAndUpdateOperatorId(6);
        assertEq(nodeRegistry.operatorIdForExcessDeposit(), operatorId1);
        assertEq(selectedOperatorCapacity[operatorId1], pubkeys.length);
        assertEq(selectedOperatorCapacity[operatorId2], pubkeys1.length);
        vm.startPrank(address(permissionedPool));
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys[0]);
        nodeRegistry.updateQueuedValidatorIndex(operatorId1, 1);
        uint256[] memory selectedOperatorCapacity1 = nodeRegistry.allocateValidatorsAndUpdateOperatorId(6);
        assertEq(nodeRegistry.operatorIdForExcessDeposit(), operatorId1);
        assertEq(selectedOperatorCapacity1[operatorId1], pubkeys.length - 1);
        assertEq(selectedOperatorCapacity1[operatorId2], pubkeys1.length);
        uint256[] memory selectedOperatorCapacity2 = nodeRegistry.allocateValidatorsAndUpdateOperatorId(5);
        assertEq(nodeRegistry.operatorIdForExcessDeposit(), operatorId1);
        assertEq(selectedOperatorCapacity2[operatorId1], pubkeys.length - 1);
        assertEq(selectedOperatorCapacity2[operatorId2], pubkeys1.length);
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys1[0]);
        nodeRegistry.markValidatorStatusAsPreDeposit(pubkeys1[1]);
        nodeRegistry.updateQueuedValidatorIndex(operatorId2, 2);
        uint256[] memory selectedOperatorCapacity3 = nodeRegistry.allocateValidatorsAndUpdateOperatorId(3);
        assertEq(nodeRegistry.operatorIdForExcessDeposit(), operatorId2);
        assertEq(selectedOperatorCapacity3[operatorId1], pubkeys.length - 1);
        assertEq(selectedOperatorCapacity3[operatorId2], pubkeys1.length - 2);
    }

    function test_DeactivateNodeOperator(uint64 __opAddrSeed, uint64 _opRewardAddrSeed) public {
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        whitelistOperator(operatorAddr);
        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP', payable(opRewardAddr));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        vm.startPrank(staderManager);
        nodeRegistry.deactivateNodeOperator(operatorId);
        vm.expectRevert(IPermissionedNodeRegistry.OperatorAlreadyDeactivate.selector);
        nodeRegistry.deactivateNodeOperator(operatorId);
    }

    function test_ActivateNodeOperator(uint64 __opAddrSeed, uint64 _opRewardAddrSeed) public {
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        whitelistOperator(operatorAddr);
        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator('testOP', opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        vm.startPrank(staderManager);
        vm.expectRevert(IPermissionedNodeRegistry.OperatorAlreadyActive.selector);
        nodeRegistry.activateNodeOperator(operatorId);
        nodeRegistry.deactivateNodeOperator(operatorId);
        nodeRegistry.activateNodeOperator(operatorId);
    }

    function test_getCollateralETH() public {
        uint256 collateralETH = nodeRegistry.getCollateralETH();
        assertEq(collateralETH, 0);
    }

    function whitelistOperator(address operatorAddr) internal {
        address[] memory whitelistAddr = new address[](1);
        whitelistAddr[0] = operatorAddr;
        vm.prank(staderManager);
        nodeRegistry.whitelistPermissionedNOs(whitelistAddr);
    }

    function getValidatorKeys()
        internal
        pure
        returns (
            bytes[] memory,
            bytes[] memory,
            bytes[] memory
        )
    {
        bytes[] memory pubkeys = new bytes[](3);
        bytes[] memory preDepositSignature = new bytes[](3);
        bytes[] memory depositSignature = new bytes[](3);
        pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        pubkeys[1] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a';
        pubkeys[2] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d69183518a';
        preDepositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        preDepositSignature[
            1
        ] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849958';
        preDepositSignature[
            2
        ] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278b';
        depositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        depositSignature[
            1
        ] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849958';
        depositSignature[
            2
        ] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278b';

        return (pubkeys, preDepositSignature, depositSignature);
    }

    function getDifferentSetOfValidatorKeys()
        internal
        pure
        returns (
            bytes[] memory,
            bytes[] memory,
            bytes[] memory
        )
    {
        bytes[] memory pubkeys = new bytes[](3);
        bytes[] memory preDepositSignature = new bytes[](3);
        bytes[] memory depositSignature = new bytes[](3);
        pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336751';
        pubkeys[1] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6b';
        pubkeys[2] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d69183518b';
        preDepositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        preDepositSignature[
            1
        ] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849959';
        preDepositSignature[
            2
        ] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278c';
        depositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        depositSignature[
            1
        ] = '0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849959';
        depositSignature[
            2
        ] = '0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278c';

        return (pubkeys, preDepositSignature, depositSignature);
    }
}
