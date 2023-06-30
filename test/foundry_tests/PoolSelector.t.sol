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

    address staderStakePoolManager;

    StaderConfig staderConfig;
    PoolSelector poolSelector;
    PoolUtilsMockForDepositFlow poolUtils;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);
        staderStakePoolManager = vm.addr(110);

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
        TransparentUpgradeableProxy poolSelectorProxy = new TransparentUpgradeableProxy(
            address(poolSelectorImp),
            address(admin),
            ''
        );

        poolSelector = PoolSelector(address(poolSelectorProxy));
        poolSelector.initialize(staderAdmin, address(staderConfig));

        poolUtils = new PoolUtilsMockForDepositFlow(address(0), address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateStakePoolManager(staderStakePoolManager);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PoolSelector poolSelectorImp = new PoolSelector();
        TransparentUpgradeableProxy poolSelectorProxy = new TransparentUpgradeableProxy(
            address(poolSelectorImp),
            address(admin),
            ''
        );

        poolSelector = PoolSelector(address(poolSelectorProxy));
        poolSelector.initialize(staderAdmin, address(staderConfig));
    }

    function test_PoolSelectorInitialize() public {
        assertEq(address(poolSelector.staderConfig()), address(staderConfig));
        assertEq(poolSelector.poolAllocationMaxSize(), 50);
        assertEq(poolSelector.poolIdArrayIndexForExcessDeposit(), 0);
        assertEq(poolSelector.POOL_WEIGHTS_SUM(), 10000);
        assertTrue(poolSelector.hasRole(poolSelector.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_updatePoolWeights() public {
        uint256[] memory poolWeight = new uint256[](2);
        uint256[] memory invalidPoolWeight = new uint256[](2);
        uint256[] memory invalidSizePoolWeight = new uint256[](3);
        poolWeight[0] = 7000;
        poolWeight[1] = 3000;
        invalidPoolWeight[0] = 8000;
        invalidPoolWeight[1] = 3000;
        invalidSizePoolWeight[0] = 2000;
        invalidSizePoolWeight[1] = 4000;
        invalidSizePoolWeight[2] = 4000;

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        poolSelector.updatePoolWeights(poolWeight);

        vm.startPrank(staderManager);
        vm.expectRevert(IPoolSelector.InvalidNewTargetInput.selector);
        poolSelector.updatePoolWeights(invalidSizePoolWeight);

        vm.expectRevert(IPoolSelector.InvalidSumOfPoolWeights.selector);
        poolSelector.updatePoolWeights(invalidPoolWeight);

        poolSelector.updatePoolWeights(poolWeight);
    }

    function test_computePoolAllocationForDeposit() public {
        uint256[] memory poolWeight = new uint256[](2);
        poolWeight[0] = 7000;
        poolWeight[1] = 3000;
        vm.prank(staderManager);
        poolSelector.updatePoolWeights(poolWeight);
        vm.prank(operator);
        poolSelector.updatePoolAllocationMaxSize(1000);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 2),
            abi.encode(50)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(100)
        );

        assertEq(poolSelector.computePoolAllocationForDeposit(2, 50), 0);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 1),
            abi.encode(0)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 2),
            abi.encode(0)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(0)
        );

        assertEq(poolSelector.computePoolAllocationForDeposit(1, 357), 249);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 1),
            abi.encode(249)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(249)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2, 94), 94);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 2),
            abi.encode(94)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(343)
        );

        assertEq(poolSelector.computePoolAllocationForDeposit(1, 357), 241);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 1),
            abi.encode(490)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(584)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2, 101), 101);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 2),
            abi.encode(195)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(685)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(1, 357), 239);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getActiveValidatorCountByPool.selector, 1),
            abi.encode(729)
        );

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getTotalActiveValidatorCount.selector),
            abi.encode(924)
        );
        assertEq(poolSelector.computePoolAllocationForDeposit(2, 103), 103);
    }

    function test_poolAllocationForExcessETHDeposit() public {
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        poolSelector.poolAllocationForExcessETHDeposit(2500 ether);

        assertEq(poolSelector.poolIdArrayIndexForExcessDeposit(), 0);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getQueuedValidatorCountByPool.selector, 1),
            abi.encode(100)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getQueuedValidatorCountByPool.selector, 2),
            abi.encode(0)
        );
        vm.prank(staderStakePoolManager);
        (uint256[] memory selectedPoolCapacity, uint8[] memory poolIdArray) = poolSelector
            .poolAllocationForExcessETHDeposit(2500 ether);

        assertEq(poolIdArray[0], 1);
        assertEq(poolIdArray[1], 2);
        assertEq(selectedPoolCapacity[0], 50);
        assertEq(selectedPoolCapacity[1], 0);
        assertEq(poolSelector.poolIdArrayIndexForExcessDeposit(), 1);

        vm.prank(operator);
        poolSelector.updatePoolAllocationMaxSize(1000);
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getQueuedValidatorCountByPool.selector, 1),
            abi.encode(100)
        );
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getQueuedValidatorCountByPool.selector, 2),
            abi.encode(100)
        );
        vm.prank(staderStakePoolManager);
        (uint256[] memory selectedPoolCapacity1, uint8[] memory poolIdArray1) = poolSelector
            .poolAllocationForExcessETHDeposit(4000 ether);
        assertEq(poolIdArray1[0], 1);
        assertEq(poolIdArray1[1], 2);
        assertEq(selectedPoolCapacity1[0], 28);
        assertEq(selectedPoolCapacity1[1], 100);
        assertEq(poolSelector.poolIdArrayIndexForExcessDeposit(), 1);
    }

    function test_updatePoolAllocationMaxSize() public {
        vm.expectRevert(UtilLib.CallerNotOperator.selector);
        poolSelector.updatePoolAllocationMaxSize(1000);
        vm.prank(operator);
        poolSelector.updatePoolAllocationMaxSize(1000);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        poolSelector.updateStaderConfig(newStaderConfig);
        assertEq(address(poolSelector.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        poolSelector.updateStaderConfig(newStaderConfig);
        assertEq(address(poolSelector.staderConfig()), newStaderConfig);
    }
}
