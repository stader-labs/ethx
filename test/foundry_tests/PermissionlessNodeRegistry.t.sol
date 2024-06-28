// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/factory/VaultFactory.sol";
import "../../contracts/NodeELRewardVault.sol";
import "../../contracts/PermissionlessNodeRegistry.sol";

import "../mocks/PenaltyMock.sol";
import "../mocks/SocializingPoolMock.sol";
import "../mocks/SDCollateralMock.sol";
import "../mocks/StaderOracleMock.sol";
import "../mocks/PermissionlessPoolMock.sol";
import "../mocks/StaderInsuranceFundMock.sol";
import "../mocks/StakePoolManagerMock.sol";
import "../mocks/OperatorRewardsCollectorMock.sol";
import "../mocks/PoolUtilsMockForDepositFlow.sol";

import "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract PermissionlessNodeRegistryTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionlessNodeRegistry nodeRegistry;
    PoolUtilsMockForDepositFlow poolUtils;

    SocializingPoolMock socializingPoolMock;
    StaderOracleMock staderOracle;
    SDCollateralMock sdCollateral;
    PermissionlessPoolMock permissionlessPool;

    function setUp() public {
        vm.clearMockedCalls();
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);
        address ethDepositAddr = vm.addr(103);

        PenaltyMock penalty = new PenaltyMock();
        socializingPoolMock = new SocializingPoolMock();
        staderOracle = new StaderOracleMock();
        sdCollateral = new SDCollateralMock();
        NodeELRewardVault nodeELImpl = new NodeELRewardVault();
        StakePoolManagerMock poolManager = new StakePoolManagerMock();
        StaderInsuranceFundMock insuranceFund = new StaderInsuranceFundMock();
        OperatorRewardsCollectorMock rewardCollector = new OperatorRewardsCollectorMock();
        permissionlessPool = new PermissionlessPoolMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        VaultFactory vaultImp = new VaultFactory();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vaultImp), address(admin), "");

        vaultFactory = VaultFactory(address(vaultProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        PermissionlessNodeRegistry nodeRegistryImpl = new PermissionlessNodeRegistry();
        TransparentUpgradeableProxy nodeRegistryProxy = new TransparentUpgradeableProxy(
            address(nodeRegistryImpl),
            address(admin),
            ""
        );
        nodeRegistry = PermissionlessNodeRegistry(address(nodeRegistryProxy));
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
        staderConfig.updatePermissionlessPool(address(permissionlessPool));
        staderConfig.updateOperatorRewardsCollector(address(rewardCollector));
        staderConfig.updateNodeELRewardImplementation(address(nodeELImpl));
        staderConfig.updatePermissionlessSocializingPool(address(socializingPoolMock));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vaultFactory.grantRole(vaultFactory.NODE_REGISTRY_CONTRACT(), address(nodeRegistry));
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PermissionlessNodeRegistry nodeRegistryImpl = new PermissionlessNodeRegistry();
        TransparentUpgradeableProxy nodeRegistryProxy = new TransparentUpgradeableProxy(
            address(nodeRegistryImpl),
            address(admin),
            ""
        );
        nodeRegistry = PermissionlessNodeRegistry(address(nodeRegistryProxy));
        nodeRegistry.initialize(staderAdmin, address(staderConfig));
    }

    function test_permissionlessNodeRegistryInitialize() public {
        assertEq(address(nodeRegistry.staderConfig()), address(staderConfig));
        assertEq(nodeRegistry.nextValidatorId(), 1);
        assertEq(nodeRegistry.nextOperatorId(), 1);
        assertEq(nodeRegistry.inputKeyCountLimit(), 30);
        assertEq(nodeRegistry.maxNonTerminalKeyPerOperator(), 50);
        assertEq(nodeRegistry.verifiedKeyBatchSize(), 50);
        assertTrue(nodeRegistry.hasRole(nodeRegistry.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_OnboardOperatorWithOptIn(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        vm.startPrank(operatorAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.poolAddressById.selector),
            abi.encode(address(0))
        );
        vm.expectRevert(INodeRegistry.DuplicatePoolIDOrPoolNotAdded.selector);
        nodeRegistry.onboardNodeOperator(true, _operatorName, opRewardAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.poolAddressById.selector),
            abi.encode(address(permissionlessPool))
        );
        address output = nodeRegistry.onboardNodeOperator(true, _operatorName, opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        assertEq(output, address(socializingPoolMock));
        assertEq(nodeRegistry.getOperatorRewardAddress(operatorId), opRewardAddr);
        assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        assertNotEq(output, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
        vm.stopPrank();
    }

    function test_OnboardOperatorWithOptOut(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        vm.prank(operatorAddr);
        address output = nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        address nodeELVault = vaultFactory.computeNodeELRewardVaultAddress(nodeRegistry.POOL_ID(), operatorId);
        assertEq(output, nodeELVault);
        assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        assertEq(output, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
        assertEq(nodeRegistry.isExistingOperator(operatorAddr), true);
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
        vm.startPrank(operatorAddr);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.isExistingOperator.selector),
            abi.encode(true)
        );
        vm.expectRevert(INodeRegistry.OperatorAlreadyOnBoardedInProtocol.selector);
        nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
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
        vm.startPrank(operatorAddr);
        vm.expectRevert("Pausable: paused");
        nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
        vm.stopPrank();
        vm.prank(staderManager);
        nodeRegistry.unpause();
    }

    function test_addValidatorKeysWithUtilizeSD() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeysWithUtilizeSD{ value: 12 ether }(
            "testReferral",
            0,
            pubkeys,
            preDepositSignature,
            depositSignature
        );
        vm.stopPrank();
        uint256 nextValidatorId = nodeRegistry.nextValidatorId();
        assertEq(nextValidatorId, 4);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[0]), 1);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[2]), 3);
        assertEq(nodeRegistry.isExistingPubkey(pubkeys[0]), true);
    }

    function test_addValidatorKeys() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        uint256 nextValidatorId = nodeRegistry.nextValidatorId();
        assertEq(nextValidatorId, 4);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[0]), 1);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[2]), 3);
        assertEq(nodeRegistry.isExistingPubkey(pubkeys[0]), true);
    }

    function testAddValidatorKeysNotEnoughSDCollateral() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.hasEnoughSDCollateral.selector),
            abi.encode(false)
        );
        vm.expectRevert(INodeRegistry.NotEnoughSDCollateral.selector);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithMisMatchingInputs() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory preDepositSignature = new bytes[](1);
        bytes[] memory depositSignature = new bytes[](0);
        pubkeys[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        preDepositSignature[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5";
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.expectRevert(INodeRegistry.MisMatchingInputKeysSize.selector);
        nodeRegistry.addValidatorKeys{ value: 4 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithInvalidKeyCount() public {
        bytes[] memory pubkeys = new bytes[](0);
        bytes[] memory preDepositSignature = new bytes[](0);
        bytes[] memory depositSignature = new bytes[](0);
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.expectRevert(INodeRegistry.InvalidKeyCount.selector);
        nodeRegistry.addValidatorKeys{ value: 4 ether }(pubkeys, preDepositSignature, depositSignature);
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
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.expectRevert(INodeRegistry.MaxKeyLimitReached.selector);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithInvalidBondETH() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.expectRevert(IPermissionlessNodeRegistry.InvalidBondEthValue.selector);
        nodeRegistry.addValidatorKeys{ value: 2 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_addValidatorKeysWithInsufficientSDCollateral() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        vm.mockCall(
            address(sdCollateral),
            abi.encodeWithSelector(ISDCollateral.hasEnoughSDCollateral.selector),
            abi.encode(false)
        );
        vm.expectRevert(INodeRegistry.NotEnoughSDCollateral.selector);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_markReadyToDepositValidator() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.startPrank(operator);
        vm.deal(operator, 100 ether);
        nodeRegistry.updateVerifiedKeysBatchSize(2);
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        bytes[] memory readyToDepositKeys = new bytes[](1);
        bytes[] memory frontRunKeys = new bytes[](1);
        bytes[] memory invalidSigKeys = new bytes[](1);
        readyToDepositKeys[0] = pubkeys[0];
        frontRunKeys[0] = pubkeys[1];
        invalidSigKeys[0] = pubkeys[2];
        uint256 readyToDepositValidatorId = nodeRegistry.validatorIdByPubkey(readyToDepositKeys[0]);
        uint256 frontRunValidatorId = nodeRegistry.validatorIdByPubkey(frontRunKeys[0]);
        uint256 invalidSigValidatorId = nodeRegistry.validatorIdByPubkey(invalidSigKeys[0]);
        vm.startPrank(address(staderOracle));
        vm.expectRevert(INodeRegistry.TooManyVerifiedKeysReported.selector);
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        vm.stopPrank();
        vm.prank(operator);
        nodeRegistry.updateVerifiedKeysBatchSize(50);
        vm.startPrank(address(staderOracle));
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        vm.expectRevert(INodeRegistry.UNEXPECTED_STATUS.selector);
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        vm.stopPrank();
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), readyToDepositKeys.length);
        (ValidatorStatus readyToDepositStatus, , , , , , , ) = nodeRegistry.validatorRegistry(
            readyToDepositValidatorId
        );
        (ValidatorStatus frontRunStatus, , , , , , , ) = nodeRegistry.validatorRegistry(frontRunValidatorId);
        (ValidatorStatus invalidSigStatus, , , , , , , ) = nodeRegistry.validatorRegistry(invalidSigValidatorId);
        require(readyToDepositStatus == ValidatorStatus.PRE_DEPOSIT);
        require(frontRunStatus == ValidatorStatus.FRONT_RUN);
        require(invalidSigStatus == ValidatorStatus.INVALID_SIGNATURE);
        startHoax(operator);
        vm.expectRevert(INodeRegistry.OperatorIsDeactivate.selector);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
    }

    function test_withdrawnValidators() public {
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();

        vm.prank(operator);
        staderConfig.updateWithdrawnKeysBatchSize(1);
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        uint256 validatorId2 = nodeRegistry.validatorIdByPubkey(pubkeys[1]);
        uint256 validatorId3 = nodeRegistry.validatorIdByPubkey(pubkeys[2]);

        vm.startPrank(address(permissionlessPool));
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

    function test_updateNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex) public {
        vm.assume(_nextQueuedValidatorIndex > 0);
        vm.startPrank(address(permissionlessPool));
        nodeRegistry.updateNextQueuedValidatorIndex(_nextQueuedValidatorIndex);
        uint256 nextQueuedValidatorIndex = nodeRegistry.nextQueuedValidatorIndex();
        assertEq(nextQueuedValidatorIndex, _nextQueuedValidatorIndex);
    }

    function test_changeSocializingPoolStateWithZeroCoolDown(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        vm.startPrank(operatorAddr);
        address feeRecipientAddressBefore = nodeRegistry.onboardNodeOperator(true, _operatorName, opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        assertEq(feeRecipientAddressBefore, address(socializingPoolMock));
        address feeRecipientAddressAfter = nodeRegistry.changeSocializingPoolState(false);
        assertEq(feeRecipientAddressAfter, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
        assertEq(nodeRegistry.getSocializingPoolStateChangeBlock(operatorId), block.number);
    }

    function test_changeSocializingPoolStateWithSomeCoolDown(
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
        staderConfig.updateSocializingPoolOptInCoolingPeriod(50);
        vm.startPrank(operatorAddr);
        address feeRecipientAddressBefore = nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
        uint256 lastStateChangedBlock = block.number;
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        assertEq(feeRecipientAddressBefore, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
        uint256 latestStateChangeBlock = lastStateChangedBlock + 50;
        vm.roll(latestStateChangeBlock);
        vm.deal(feeRecipientAddressBefore, 1 ether);
        address feeRecipientAddressAfter = nodeRegistry.changeSocializingPoolState(true);
        assertEq(address(feeRecipientAddressBefore).balance, 0);
        assertEq(feeRecipientAddressAfter, address(socializingPoolMock));
        assertEq(nodeRegistry.getSocializingPoolStateChangeBlock(operatorId), latestStateChangeBlock);
    }

    function testFail_changeSocializingPoolStateWithSameState(
        string calldata _operatorName,
        uint64 __opAddrSeed,
        uint64 _opRewardAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        vm.assume(_opRewardAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        address payable opRewardAddr = payable(vm.addr(_opRewardAddrSeed));
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
        nodeRegistry.changeSocializingPoolState(false);
    }

    function testFail_changeSocializingPoolStateDuringCoolDown(
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
        staderConfig.updateSocializingPoolOptInCoolingPeriod(50);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);
        nodeRegistry.changeSocializingPoolState(true);
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

        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, opRewardAddr);

        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);

        // propose new reward addr
        vm.expectRevert(INodeRegistry.CallerNotExistingRewardAddress.selector);
        vm.prank(operatorAddr);
        nodeRegistry.proposeRewardAddress(operatorAddr, newOPRewardAddr);

        // passed wrong new reward address by mistake
        vm.prank(opRewardAddr);
        nodeRegistry.proposeRewardAddress(operatorAddr, vm.addr(666));

        vm.prank(opRewardAddr);
        nodeRegistry.proposeRewardAddress(operatorAddr, newOPRewardAddr);

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
        nodeRegistry.proposeRewardAddress(operatorAddr, newOPRewardAddr);

        // it will pass if caller is address(0), which is not possible
        vm.prank(address(0));
        nodeRegistry.proposeRewardAddress(operatorAddr, newOPRewardAddr);
    }

    function test_updateOperatorRewardAddressWithZeroRewardAddr(
        string calldata _operatorName,
        uint64 __opAddrSeed
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        vm.prank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, payable(operatorAddr));

        vm.expectRevert(UtilLib.ZeroAddress.selector);
        vm.prank(operatorAddr);
        nodeRegistry.proposeRewardAddress(operatorAddr, payable(address(0)));
    }

    function test_updateOperatorName(string calldata _operatorName, uint64 __opAddrSeed) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, payable(operatorAddr));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        string memory newOpName = string(abi.encodePacked(_operatorName, "test"));
        nodeRegistry.updateOperatorName(newOpName);
        (, , string memory operatorName, , ) = nodeRegistry.operatorStructById(operatorId);
        assertEq(operatorName, newOpName);
        vm.stopPrank();
    }

    function test_updateOperatorNameWithInActiveOperator(string calldata _operatorName) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        string memory newOpName = string(abi.encodePacked(_operatorName, "test"));
        vm.expectRevert(INodeRegistry.OperatorNotOnBoarded.selector);
        nodeRegistry.updateOperatorName(newOpName);
    }

    function test_updateOperatorNameWithInvalidName(string calldata _operatorName, uint64 __opAddrSeed) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(__opAddrSeed > 0);
        address operatorAddr = vm.addr(__opAddrSeed);
        vm.startPrank(operatorAddr);
        nodeRegistry.onboardNodeOperator(false, _operatorName, payable(operatorAddr));
        string memory newOpName = string(abi.encodePacked(""));
        vm.expectRevert(PoolUtilsMockForDepositFlow.EmptyNameString.selector);
        nodeRegistry.updateOperatorName(newOpName);
    }

    function test_increaseTotalActiveValidatorCount(uint256 _count) public {
        uint256 totalActiveValidatorsBefore = nodeRegistry.totalActiveValidatorCount();
        vm.prank(address(permissionlessPool));
        nodeRegistry.increaseTotalActiveValidatorCount(_count);
        uint256 totalActiveValidatorsAfter = nodeRegistry.totalActiveValidatorCount();
        assertEq(totalActiveValidatorsAfter - totalActiveValidatorsBefore, _count);
    }

    function test_increaseTotalActiveValidatorCountCallerNotPermissionlessPool(uint256 _count) public {
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        nodeRegistry.increaseTotalActiveValidatorCount(_count);
    }

    function test_transferCollateralToPool(uint256 _amount) public {
        uint256 permissionlessPoolBalanceBefore = address(permissionlessPool).balance;
        vm.deal(address(nodeRegistry), _amount);
        vm.prank(address(permissionlessPool));
        nodeRegistry.transferCollateralToPool(_amount);
        uint256 permissionlessPoolBalanceAfter = address(permissionlessPool).balance;
        assertEq(permissionlessPoolBalanceAfter - permissionlessPoolBalanceBefore, _amount);
    }

    function test_transferCollateralToPoolCallerNotPermissionlessPool(uint256 _amount) public {
        vm.deal(address(nodeRegistry), _amount);
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        nodeRegistry.transferCollateralToPool(_amount);
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

        startHoax(operatorAddr);
        nodeRegistry.onboardNodeOperator(true, "testOP", opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
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

        startHoax(operatorAddr);
        nodeRegistry.onboardNodeOperator(true, "testOP", opRewardAddr);
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
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

        vm.startPrank(operator);
        vm.deal(operator, 100 ether);
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        bytes[] memory readyToDepositKeys = new bytes[](3);
        bytes[] memory frontRunKeys = new bytes[](0);
        bytes[] memory invalidSigKeys = new bytes[](0);
        readyToDepositKeys[0] = pubkeys[0];
        readyToDepositKeys[1] = pubkeys[1];
        readyToDepositKeys[2] = pubkeys[2];
        vm.prank(address(staderOracle));
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), readyToDepositKeys.length);
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        uint256 validatorId2 = nodeRegistry.validatorIdByPubkey(pubkeys[1]);
        uint256 validatorId3 = nodeRegistry.validatorIdByPubkey(pubkeys[2]);
        vm.startPrank(address(permissionlessPool));
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

        vm.startPrank(operator);
        vm.deal(operator, 100 ether);
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(address(this)));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        bytes[] memory readyToDepositKeys = new bytes[](1);
        bytes[] memory frontRunKeys = new bytes[](0);
        bytes[] memory invalidSigKeys = new bytes[](0);
        readyToDepositKeys[0] = pubkeys[0];
        vm.prank(address(staderOracle));
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
        assertEq(nodeRegistry.getTotalQueuedValidatorCount(), readyToDepositKeys.length);
        uint256 validatorId1 = nodeRegistry.validatorIdByPubkey(pubkeys[0]);
        vm.startPrank(address(permissionlessPool));
        nodeRegistry.updateDepositStatusAndBlock(validatorId1);
        nodeRegistry.increaseTotalActiveValidatorCount(1);
        vm.stopPrank();
        vm.expectRevert(INodeRegistry.PageNumberIsZero.selector);
        nodeRegistry.getAllActiveValidators(pageNumber, _pageSize);
    }

    function test_getValidatorsByOperator() public {
        address op = vm.addr(445);
        (
            bytes[] memory pubkeys,
            bytes[] memory preDepositSignature,
            bytes[] memory depositSignature
        ) = getValidatorKeys();
        startHoax(op);
        nodeRegistry.onboardNodeOperator(true, "testOP", payable(op));
        nodeRegistry.addValidatorKeys{ value: 12 ether }(pubkeys, preDepositSignature, depositSignature);
        Validator[] memory validators = nodeRegistry.getValidatorsByOperator(op, 1, 100);
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

    function test_getNodeELVaultAddressForOptOutOperators(uint256 _pageNumber, uint256 _pageSize) public {
        vm.assume(_pageNumber > 0 && _pageNumber < 1000);
        vm.assume(_pageSize < 10000);
        address op1 = vm.addr(10000000);
        address op2 = vm.addr(20000000);
        address op3 = vm.addr(30000000);
        address op4 = vm.addr(40000000);
        vm.prank(op1);
        nodeRegistry.onboardNodeOperator(false, "op1", payable(op1));
        vm.prank(op2);
        nodeRegistry.onboardNodeOperator(false, "op2", payable(op2));
        vm.prank(op3);
        nodeRegistry.onboardNodeOperator(false, "op3", payable(op3));
        vm.prank(op4);
        nodeRegistry.onboardNodeOperator(false, "op4", payable(op4));
        address[] memory operatorAddr = nodeRegistry.getAllNodeELVaultAddress(_pageNumber, _pageSize);
        uint256 startIndex = (_pageNumber - 1) * _pageSize + 1;
        uint256 nextOperatorId = nodeRegistry.nextOperatorId();
        uint256 expectedOptOutOperatorCount = startIndex >= nextOperatorId
            ? 0
            : Math.min(_pageSize, nextOperatorId - startIndex);
        assertEq(operatorAddr.length, expectedOptOutOperatorCount);
    }

    function test_getNodeELVaultAddressForOptOutOperatorsWithZeroPageNumber(uint256 _pageSize) public {
        uint256 pageNumber = 0;
        vm.assume(_pageSize < 10000);
        address op1 = vm.addr(10000000);
        address op2 = vm.addr(20000000);
        address op3 = vm.addr(30000000);
        address op4 = vm.addr(40000000);
        vm.prank(op1);
        nodeRegistry.onboardNodeOperator(false, "op1", payable(op1));
        vm.prank(op2);
        nodeRegistry.onboardNodeOperator(false, "op2", payable(op2));
        vm.prank(op3);
        nodeRegistry.onboardNodeOperator(false, "op3", payable(op3));
        vm.prank(op4);
        nodeRegistry.onboardNodeOperator(false, "op4", payable(op4));
        vm.expectRevert(INodeRegistry.PageNumberIsZero.selector);
        nodeRegistry.getAllNodeELVaultAddress(pageNumber, _pageSize);
    }

    function test_getCollateralETH() public {
        assertEq(nodeRegistry.getCollateralETH(), 4 ether);
    }

    function getValidatorKeys() internal pure returns (bytes[] memory, bytes[] memory, bytes[] memory) {
        bytes[] memory pubkeys = new bytes[](3);
        bytes[] memory preDepositSignature = new bytes[](3);
        bytes[] memory depositSignature = new bytes[](3);
        pubkeys[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        pubkeys[1] = "0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a";
        pubkeys[2] = "0x8c6c13d3cc575bd0e679481d6a730ee19e73d69183518a";
        preDepositSignature[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5";
        preDepositSignature[
            1
        ] = "0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849958";
        preDepositSignature[
            2
        ] = "0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278b";
        depositSignature[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5";
        depositSignature[
            1
        ] = "0xa119a476cd0f30f5117b823c5732c66199136f18e55e6a616a52a69f1986d8b08055bccbf7169baf47289fa2849958";
        depositSignature[
            2
        ] = "0x8c6c13d3cc575bd0e679481d6a730ee19e73d6918351b2d42eb77ff690664348a5060ccb8938df9cedfd2998d7278b";

        return (pubkeys, preDepositSignature, depositSignature);
    }
}
