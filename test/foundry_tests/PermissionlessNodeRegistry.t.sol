pragma solidity ^0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/factory/VaultFactory.sol";
import "../../contracts/PermissionlessNodeRegistry.sol";

import "../mocks/PoolUtilsMock.sol";
import "../mocks/SocializingPoolMock.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

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
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(
            address(vaultImp),
            address(admin),
            ""
        );

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

        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateVaultFactory(address(vaultFactory));
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
            ""
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
        uint256 _operatorAddress,
        address payable _operatorRewardAddress
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(_operatorRewardAddress != address(0));
        vm.prank(_operatorAddress);
        address out = nodeRegistry.onboardNodeOperator(true, _operatorName, _operatorRewardAddress);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(_operatorAddress);
        assertEq(out, address(socializingPoolMock));
        //failing with
        //assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        assertEq(block.number, nodeRegistry.socializingPoolStateChangeBlock(operatorId));
        assertNotEq(out, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
    }

    function test_OnboardOperatorWithOptOut(
        string calldata _operatorName,
        address _operatorAddress,
        address payable _operatorRewardAddress
    ) public {
        vm.assume(bytes(_operatorName).length > 0 && bytes(_operatorName).length < 255);
        vm.assume(_operatorRewardAddress != address(0));
        vm.prank(_operatorAddress);
        address out = nodeRegistry.onboardNodeOperator(false, _operatorName, _operatorRewardAddress);
        uint256 operatorId = nodeRegistry.operatorIDByAddress(_operatorAddress);
        address nodeELVault = vaultFactory.computeNodeELRewardVaultAddress(nodeRegistry.POOL_ID(), operatorId);
        assertEq(out, nodeELVault);
        //failing with
        //assertEq(nodeRegistry.socializingPoolStateChangeBlock(operatorId), block.number);
        //passing with
        assertEq(block.number, nodeRegistry.socializingPoolStateChangeBlock(operatorId));
        assertEq(out, nodeRegistry.nodeELRewardVaultByOperatorId(operatorId));
    }

    function test_addValidatorKeys(bytes calldata _pubkey, bytes calldata _preDepositSig, bytes calldata _depositSig){
        vm.assume(_pubkey.length == 48);
        vm.assume(_preDepositSig.length == 96);
        vm.assume(_depositSig.length == 96);
        vm.string()

    }
}
