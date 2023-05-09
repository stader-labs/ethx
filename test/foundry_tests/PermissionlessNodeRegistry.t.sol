pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/factory/VaultFactory.sol';
import '../../contracts/PermissionlessNodeRegistry.sol';

import '../mocks/PenaltyMock.sol';
import '../mocks/SocializingPoolMock.sol';
import '../mocks/SDCollateralMock.sol';
import '../mocks/StaderOracleMock.sol';
import '../mocks/PermissionlessPoolMock.sol';
import '../mocks/StaderInsuranceFundMock.sol';
import '../mocks/StakePoolManagerMock.sol';
import '../mocks/PoolUtilsMockForDepositFlow.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PermissionlessNodeRegistryTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionlessNodeRegistry nodeRegistry;

    SocializingPoolMock socializingPoolMock;
    StaderOracleMock staderOracle;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);
        address ethDepositAddr = vm.addr(103);

        PenaltyMock penalty = new PenaltyMock();
        socializingPoolMock = new SocializingPoolMock();
        staderOracle = new StaderOracleMock();
        SDCollateralMock sdCollateral = new SDCollateralMock();
        StakePoolManagerMock poolManager = new StakePoolManagerMock();
        StaderInsuranceFundMock insuranceFund = new StaderInsuranceFundMock();
        PermissionlessPoolMock permissionlessPool = new PermissionlessPoolMock();
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

        PermissionlessNodeRegistry nodeRegistryImpl = new PermissionlessNodeRegistry();
        TransparentUpgradeableProxy nodeRegistryProxy = new TransparentUpgradeableProxy(
            address(nodeRegistryImpl),
            address(admin),
            ''
        );
        nodeRegistry = PermissionlessNodeRegistry(address(nodeRegistryProxy));
        nodeRegistry.initialize(staderAdmin, address(staderConfig));
        PoolUtilsMockForDepositFlow poolUtils = new PoolUtilsMockForDepositFlow(address(nodeRegistry));
        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updatePenaltyContract(address(penalty));
        staderConfig.updateStakePoolManager(address(poolManager));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updateStaderInsuranceFund(address(insuranceFund));
        staderConfig.updatePermissionlessPool(address(permissionlessPool));
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
            ''
        );
        nodeRegistry = PermissionlessNodeRegistry(address(nodeRegistryProxy));
        nodeRegistry.initialize(staderAdmin, address(staderConfig));
    }

    function test_permissionlessNodeRegistryInitialize() public {
        assertEq(address(nodeRegistry.staderConfig()), address(staderConfig));
        assertEq(nodeRegistry.nextValidatorId(), 1);
        assertEq(nodeRegistry.nextOperatorId(), 1);
        assertEq(nodeRegistry.inputKeyCountLimit(), 100);
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
        vm.prank(operatorAddr);
        address output = nodeRegistry.onboardNodeOperator(true, _operatorName, opRewardAddr);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operatorAddr);
        assertEq(output, address(socializingPoolMock));
        assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        assertNotEq(output, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
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
    }

    function test_addValidatorKeys() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory preDepositSignature = new bytes[](1);
        bytes[] memory depositSignature = new bytes[](1);
        pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        preDepositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        depositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, 'testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys{value: 4 ether}(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        uint256 nextValidatorId = nodeRegistry.nextValidatorId();
        assertEq(nextValidatorId, 2);
        assertEq(nodeRegistry.validatorIdByPubkey(pubkeys[0]), nextValidatorId - 1);
    }

    function test_markReadyToDepositValidator() public {
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
        startHoax(operator);
        nodeRegistry.onboardNodeOperator(true, 'testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys{value: 12 ether}(pubkeys, preDepositSignature, depositSignature);
        bytes[] memory readyToDepositKeys = new bytes[](1);
        bytes[] memory frontRunKeys = new bytes[](1);
        bytes[] memory invalidSigKeys = new bytes[](1);
        readyToDepositKeys[0] = pubkeys[0];
        frontRunKeys[0] = pubkeys[1];
        invalidSigKeys[0] = pubkeys[2];
        nodeRegistry.markValidatorReadyToDeposit(readyToDepositKeys, frontRunKeys, invalidSigKeys);
    }

    function test_withdrawnValidators() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory preDepositSignature = new bytes[](1);
        bytes[] memory depositSignature = new bytes[](1);
        pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        preDepositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        depositSignature[
            0
        ] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f5';
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, 'testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys{value: 4 ether}(pubkeys, preDepositSignature, depositSignature);
        vm.stopPrank();
        vm.prank(address(staderOracle));
        nodeRegistry.withdrawnValidators(pubkeys);
    }
}
