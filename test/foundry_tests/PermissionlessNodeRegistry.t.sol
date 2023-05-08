pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/factory/VaultFactory.sol';
import '../../contracts/PermissionlessNodeRegistry.sol';

import '../mocks/PoolUtilsMock.sol';
import '../mocks/SocializingPoolMock.sol';
import '../mocks/SDCollateralMock.sol';
import '../mocks/PermissionlessPoolMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PermissionlessNodeRegistryTest is Test {
    address staderAdmin;
    address staderManager;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionlessNodeRegistry nodeRegistry;

    SocializingPoolMock socializingPoolMock;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

        PoolUtilsMock poolUtils = new PoolUtilsMock();
        socializingPoolMock = new SocializingPoolMock();
        SDCollateralMock sdCollateral = new SDCollateralMock();
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

        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updatePermissionlessPool(address(permissionlessPool));
        staderConfig.updatePermissionlessSocializingPool(address(socializingPoolMock));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
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

    function test_addValidatorKeys(bytes calldata _pubkey, bytes calldata _signature) public {
        vm.assume(_pubkey.length == 48);
        vm.assume(_signature.length == 96);
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory preDepositSignature = new bytes[](1);
        bytes[] memory depositSignature = new bytes[](1);
        pubkeys[0] = _pubkey;
        preDepositSignature[0] = _signature;
        depositSignature[0] = _signature;
        startHoax(address(this));
        nodeRegistry.onboardNodeOperator(true, 'testOP', payable(address(this)));
        nodeRegistry.addValidatorKeys{value: 4 ether}(pubkeys, preDepositSignature, depositSignature);
    }
}
