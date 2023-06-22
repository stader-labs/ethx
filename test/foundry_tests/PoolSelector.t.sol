pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/PoolSelector.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/PoolUtilsMockForDepositFlow.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PoolSelectorTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;

    StaderConfig staderConfig;
    PoolSelector poolSelector;
    PoolUtilsMockForDepositFlow poolUtils;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        address ethDepositAddr = vm.addr(103);
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, address(ethDepositAddr));

        PoolSelector poolSelectorImp = new PoolSelector();
        TransparentUpgradeableProxy poolSelectorProxy = new TransparentUpgradeableProxy(address(poolSelectorImp), address(admin), '');

        poolSelector = PoolSelector(address(poolSelectorProxy));
        poolSelector.initialize(staderAdmin, address(staderConfig));

        poolUtils = new PoolUtilsMockForDepositFlow(address(0), address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
        vm.prank(staderManager);
        uint256[] memory poolWeight = new uint256[](2);
        poolWeight[0] = 7000;
        poolWeight[1] = 3000;
        poolSelector.updatePoolWeights(poolWeight);
        vm.prank(operator);
        poolSelector.updatePoolAllocationMaxSize(1000);
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PoolSelector poolSelectorImp = new PoolSelector();
        TransparentUpgradeableProxy poolSelectorProxy = new TransparentUpgradeableProxy(address(poolSelectorImp), address(admin), '');

        poolSelector = PoolSelector(address(poolSelectorProxy));
        poolSelector.initialize(staderAdmin, address(staderConfig));
    }

    function test_PoolSelectorInitialize() public {
        assertEq(address(poolSelector.staderConfig()), address(staderConfig));
        assertEq(poolSelector.poolAllocationMaxSize(), 1000);
        assertEq(poolSelector.poolIdArrayIndexForExcessDeposit(), 0);
        assertEq(poolSelector.POOL_WEIGHTS_SUM(), 10000);
        assertTrue(poolSelector.hasRole(poolSelector.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_computePoolAllocationForDepositWithPool1First() public {
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(0)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(0)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,10000 ether),250);
    
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(250)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,3000 ether),93);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(93)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,10000 ether),249);
    
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(499)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,3028 ether),94);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(187)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,10000 ether),249);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(748)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,3028 ether),93);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(280)
        );    
        assertEq(poolSelector.computePoolAllocationForDeposit(1,10000 ether),249);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(997)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,3028 ether),94);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(374)
        );  
        assertEq(poolSelector.computePoolAllocationForDeposit(1,10000 ether),250);
         vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(1247)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,3000 ether),93);
    }

    function test_computePoolAllocationForDepositWithPool2First() public {
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(0)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(0)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,10000 ether),93);
    
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(93)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,7024 ether),250);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(250)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,10000 ether),94);
    
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(187)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,6992 ether),249);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(499)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2,10000 ether),93);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(280)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,7024 ether),249);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(748)
        );    
        assertEq(poolSelector.computePoolAllocationForDeposit(2,10000 ether),94);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(374)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,6992 ether),249);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,1),
            abi.encode(997)
        );  
        assertEq(poolSelector.computePoolAllocationForDeposit(2,10000 ether),93);
         vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector,2),
            abi.encode(467)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1,7024 ether),250);
    }
}