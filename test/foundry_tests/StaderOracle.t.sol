pragma solidity ^0.8.10;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderOracle.sol';
import '../../contracts/SocializingPool.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderOracleTest is Test {
    address staderAdmin;
    address staderManager;

    StaderOracle staderOracle;
    SocializingPool permissionedSP;
    SocializingPool permissionlessSP;

    StaderConfig staderConfig;
    StaderTokenMock staderToken;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

        staderToken = new StaderTokenMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        StaderOracle oracleImpl = new StaderOracle();
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(admin),
            ''
        );
        staderOracle = StaderOracle(address(oracleProxy));
        staderOracle.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        permissionedSP = SocializingPool(payable(permissionedSPProxy));
        permissionedSP.initialize(staderAdmin, address(staderConfig));

        TransparentUpgradeableProxy permissionlessSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        permissionlessSP = SocializingPool(payable(permissionlessSPProxy));
        permissionlessSP.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updatePermissionedSocializingPool(address(permissionedSP));
        staderConfig.updatePermissionlessSocializingPool(address(permissionlessSP));
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();
    }

    function test_justToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        StaderOracle oracleImpl = new StaderOracle();
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(admin),
            ''
        );
        StaderOracle staderOracle2 = StaderOracle(address(oracleProxy));
        staderOracle2.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ''
        );
        SocializingPool permissionedSP2 = SocializingPool(payable(permissionedSPProxy));
        permissionedSP2.initialize(staderAdmin, address(staderConfig));
    }

    function test_initialize() public {
        assertEq(address(permissionedSP.staderConfig()), address(staderConfig));
        assertEq(address(permissionlessSP.staderConfig()), address(staderConfig));
        assertEq(address(staderOracle.staderConfig()), address(staderConfig));

        assertTrue(permissionedSP.hasRole(permissionedSP.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertTrue(permissionlessSP.hasRole(permissionlessSP.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertTrue(staderOracle.hasRole(staderOracle.DEFAULT_ADMIN_ROLE(), staderAdmin));

        assertEq(permissionedSP.initialBlock(), block.number);
        assertEq(permissionlessSP.initialBlock(), block.number);

        assertEq(staderConfig.getStaderOracle(), address(staderOracle));
        assertEq(staderConfig.getPermissionedSocializingPool(), address(permissionedSP));
        assertEq(staderConfig.getPermissionlessSocializingPool(), address(permissionlessSP));
        assertEq(staderConfig.getStaderToken(), address(staderToken));

        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }

    function test_add_remove_trustedNode() public {
        address trustedNode = vm.addr(123);
        assertEq(staderOracle.trustedNodesCount(), 0);
        assertFalse(staderOracle.isTrustedNode(trustedNode));

        vm.prank(staderManager);
        staderOracle.addTrustedNode(trustedNode);

        vm.expectRevert(IStaderOracle.NodeAlreadyTrusted.selector);
        vm.prank(staderManager);
        staderOracle.addTrustedNode(trustedNode);

        assertEq(staderOracle.trustedNodesCount(), 1);
        assertTrue(staderOracle.isTrustedNode(trustedNode));

        vm.expectRevert(IStaderOracle.NodeNotTrusted.selector);
        vm.prank(staderManager);
        staderOracle.removeTrustedNode(vm.addr(567));

        vm.prank(staderManager);
        staderOracle.removeTrustedNode(trustedNode);

        assertEq(staderOracle.trustedNodesCount(), 0);
        assertFalse(staderOracle.isTrustedNode(trustedNode));
    }

    function test_submitSDPrice() public {
        SDPriceData memory sdPriceData = SDPriceData({reportingBlockNumber: 1212, sdPriceInETH: 1});
        vm.expectRevert(IStaderOracle.NotATrustedNode.selector);
        staderOracle.submitSDPrice(sdPriceData);

        address trustedNode1 = vm.addr(701);
        vm.prank(staderManager);
        staderOracle.addTrustedNode(trustedNode1);

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InsufficientTrustedNodes.selector);
        staderOracle.submitSDPrice(sdPriceData);

        assertEq(staderOracle.MIN_TRUSTED_NODES(), 5);
        address trustedNode2 = vm.addr(702);
        address trustedNode3 = vm.addr(703);
        address trustedNode4 = vm.addr(704);
        address trustedNode5 = vm.addr(705);
        vm.startPrank(staderManager);
        staderOracle.addTrustedNode(trustedNode2);
        staderOracle.addTrustedNode(trustedNode3);
        staderOracle.addTrustedNode(trustedNode4);
        staderOracle.addTrustedNode(trustedNode5);
        vm.stopPrank();

        assertEq(block.number, 1);
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSDPrice(sdPriceData);

        (uint256 lastSDReportingBlockNumber, uint256 lastSDPrice) = staderOracle.lastReportedSDPriceData();
        assertEq(lastSDReportingBlockNumber, 0);
        sdPriceData.reportingBlockNumber = 0;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingPreviousCycleData.selector);
        staderOracle.submitSDPrice(sdPriceData);

        // lets submit after sometime
        vm.roll(5);
        assertEq(block.number, 5);

        assertEq(staderOracle.updateFrequencyMap(staderOracle.SD_PRICE_UF()), 7200);
        assertEq(staderOracle.getSDPriceReportableBlock(), 0);

        sdPriceData.reportingBlockNumber = 1;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitSDPrice(sdPriceData);

        // let's report at next reporting block
        vm.roll(7200);
        assertEq(staderOracle.getSDPriceReportableBlock(), 7200);

        sdPriceData.reportingBlockNumber = 7200;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSDPrice(sdPriceData);

        // successful submission
        vm.roll(7201);
        assertEq(staderOracle.getSDPriceReportableBlock(), 7200);

        sdPriceData.reportingBlockNumber = 7200;
        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        // trustedNode1 is trying to submit again
        vm.roll(7205);
        assertEq(staderOracle.getSDPriceReportableBlock(), 7200);

        sdPriceData.reportingBlockNumber = 7200;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitSDPrice(sdPriceData);

        // trustedNode1 is trying to submit again at next reportable block // possible
        vm.roll(2 * 7200 + 1);
        assertEq(staderOracle.getSDPriceReportableBlock(), 2 * 7200);

        sdPriceData.reportingBlockNumber = 2 * 7200;
        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        // consensus is not met even if trustedNode1 submits 5 times
        vm.roll(3 * 7200 + 1);
        assertEq(staderOracle.getSDPriceReportableBlock(), 3 * 7200);

        sdPriceData.reportingBlockNumber = 3 * 7200;
        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        // 4th time
        vm.roll(4 * 7200 + 1);
        assertEq(staderOracle.getSDPriceReportableBlock(), 4 * 7200);

        sdPriceData.reportingBlockNumber = 4 * 7200;
        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        // 5th time
        vm.roll(5 * 7200 + 1);
        assertEq(staderOracle.getSDPriceReportableBlock(), 5 * 7200);

        sdPriceData.reportingBlockNumber = 5 * 7200;
        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);
        (lastSDReportingBlockNumber, lastSDPrice) = staderOracle.lastReportedSDPriceData();

        // sdPrice has not updated, i.e. consensus not met
        assertEq(lastSDPrice, 0);

        // other trusted nodes submits for reporting block num = 7200, previous round
        assertEq(block.number, 5 * 7200 + 1); // current block number
        assertEq(staderOracle.getSDPriceReportableBlock(), 5 * 7200);

        sdPriceData.reportingBlockNumber = 7200;
        sdPriceData.sdPriceInETH = 6;
        vm.prank(trustedNode2);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitSDPrice(sdPriceData);

        sdPriceData.reportingBlockNumber = 5 * 7200;
        sdPriceData.sdPriceInETH = 6;
        vm.prank(trustedNode2);
        staderOracle.submitSDPrice(sdPriceData);

        sdPriceData.reportingBlockNumber = 5 * 7200;
        sdPriceData.sdPriceInETH = 2;
        vm.prank(trustedNode3);
        staderOracle.submitSDPrice(sdPriceData);

        sdPriceData.reportingBlockNumber = 5 * 7200;
        sdPriceData.sdPriceInETH = 4;
        vm.prank(trustedNode4);
        staderOracle.submitSDPrice(sdPriceData);

        // now consensus is met for reporting block num 5 * 7200
        // trustedNode1 manipulated the sd price if other oracles are not wrking properly
        // sdPrice submited were [1,6,2,4] => hence median = (2+4)/2 = 3
        (lastSDReportingBlockNumber, lastSDPrice) = staderOracle.lastReportedSDPriceData();
        assertEq(lastSDReportingBlockNumber, 5 * 7200);
        assertEq(lastSDPrice, 3);

        // trusted node 5 tries to submit at reportable block 5 * 7200
        sdPriceData.reportingBlockNumber = 5 * 7200;
        sdPriceData.sdPriceInETH = 4;
        vm.prank(trustedNode5);
        vm.expectRevert(IStaderOracle.ReportingPreviousCycleData.selector);
        staderOracle.submitSDPrice(sdPriceData);
    }

    function test_submitSDPrice_manipulation_not_possible_by_minority_malicious_oracles() public {
        SDPriceData memory sdPriceData = SDPriceData({reportingBlockNumber: 1212, sdPriceInETH: 1});

        assertEq(staderOracle.MIN_TRUSTED_NODES(), 5);
        address trustedNode1 = vm.addr(701);
        address trustedNode2 = vm.addr(702);
        address trustedNode3 = vm.addr(703);
        address trustedNode4 = vm.addr(704);
        address trustedNode5 = vm.addr(705);
        vm.startPrank(staderManager);
        staderOracle.addTrustedNode(trustedNode1);
        staderOracle.addTrustedNode(trustedNode2);
        staderOracle.addTrustedNode(trustedNode3);
        staderOracle.addTrustedNode(trustedNode4);
        staderOracle.addTrustedNode(trustedNode5);
        vm.stopPrank();

        // cycle 1
        vm.roll(7200 + 1);
        sdPriceData.reportingBlockNumber = 1 * 7200;
        sdPriceData.sdPriceInETH = 1;

        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        vm.prank(trustedNode2);
        staderOracle.submitSDPrice(sdPriceData);

        vm.prank(trustedNode3);
        staderOracle.submitSDPrice(sdPriceData);

        // cycle 2
        vm.roll(2 * 7200 + 1);
        sdPriceData.reportingBlockNumber = 2 * 7200;
        sdPriceData.sdPriceInETH = 1;

        vm.prank(trustedNode1);
        staderOracle.submitSDPrice(sdPriceData);

        vm.prank(trustedNode2);
        staderOracle.submitSDPrice(sdPriceData);

        vm.prank(trustedNode3);
        staderOracle.submitSDPrice(sdPriceData);

        // trustedNode4 submits for cycle 1
        sdPriceData.reportingBlockNumber = 1 * 7200;
        sdPriceData.sdPriceInETH = 1;
        vm.prank(trustedNode4);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitSDPrice(sdPriceData);

        // consensus not met yet
        (uint256 lastSDReportingBlockNumber, uint256 lastSDPrice) = staderOracle.lastReportedSDPriceData();
        assertEq(lastSDReportingBlockNumber, 0);
        assertEq(lastSDPrice, 0);

        // now sdPrice array len is 0
        // now trustedNode4 submits some random sdPrice for cycle 2 and that's gets updated
        sdPriceData.reportingBlockNumber = 2 * 7200;
        sdPriceData.sdPriceInETH = 199323;
        vm.prank(trustedNode4);
        staderOracle.submitSDPrice(sdPriceData);

        // consensus met for cycle 2
        (lastSDReportingBlockNumber, lastSDPrice) = staderOracle.lastReportedSDPriceData();
        assertEq(lastSDReportingBlockNumber, 2 * 7200);
        assertEq(lastSDPrice, 1); // but median sd price is 1
    }

    function test_submitMerkleData() public {
        address trustedNode = vm.addr(123);
        vm.prank(staderManager);
        staderOracle.addTrustedNode(trustedNode);

        RewardsData memory rewardsData = RewardsData({
            reportingBlockNumber: 12345,
            index: 1,
            merkleRoot: 0xc519b25edb1c5e9f374e77870577765f38af5983687097318df124630fbd7a70,
            poolId: 1,
            operatorETHRewards: 1234,
            userETHRewards: 1234,
            protocolETHRewards: 1234,
            operatorSDRewards: 1234
        });

        vm.expectRevert(IStaderOracle.NotATrustedNode.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);
    }
}
