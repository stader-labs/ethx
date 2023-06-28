pragma solidity ^0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderOracle.sol';
import '../../contracts/SocializingPool.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';
import '../mocks/StakePoolManagerMock.sol';
import '../mocks/PoolUtilsMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract StaderOracleTest is Test {
    address staderAdmin;
    address staderManager;

    StaderOracle staderOracle;
    SocializingPool permissionedSP;
    SocializingPool permissionlessSP;
    PoolUtilsMock poolUtils;
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

        poolUtils = new PoolUtilsMock(address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updatePermissionedSocializingPool(address(permissionedSP));
        staderConfig.updatePermissionlessSocializingPool(address(permissionlessSP));
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updatePoolUtils(address(poolUtils));
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
        assertEq(staderOracle.getSDPriceInETH(), 1);
    }

    function test_merkleReportableBlock() public {
        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getSocializingPoolAddress.selector),
            abi.encode(address(permissionlessSP))
        );

        uint256 reportableBlock = staderOracle.getMerkleRootReportableBlockByPoolId(1);
        assertEq(staderConfig.getSocializingPoolCycleDuration(), 0);
        assertEq(reportableBlock, 0);

        vm.prank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(100);

        reportableBlock = staderOracle.getMerkleRootReportableBlockByPoolId(1);
        assertEq(staderConfig.getSocializingPoolCycleDuration(), 100);
        assertEq(reportableBlock, 100);
    }

    function test_rewardDetails() public {
        (uint256 currentIndex, uint256 startBlock, uint256 endBlock) = permissionlessSP.getRewardDetails();

        assertEq(currentIndex, 1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 0); // as cycleDuration is zero

        // lets set cycle duration

        vm.prank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(100);

        (currentIndex, startBlock, endBlock) = permissionlessSP.getRewardDetails();

        assertEq(currentIndex, 1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 100);

        vm.expectRevert(ISocializingPool.InvalidCycleIndex.selector);
        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(0);

        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 100);

        vm.expectRevert(ISocializingPool.FutureCycleIndex.selector);
        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(2);
    }

    function test_submitMerkleData() public {
        RewardsData memory rewardsData = RewardsData({
            reportingBlockNumber: 12345,
            index: 1,
            merkleRoot: 0x8ca37964573a9c72087889989d8e4cc38c5d423cb9d8f9b76fbb7c6537fb0ade,
            poolId: 1,
            operatorETHRewards: 9999,
            userETHRewards: 2222,
            protocolETHRewards: 3333,
            operatorSDRewards: 4444
        });

        vm.expectRevert(IStaderOracle.NotATrustedNode.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        address trustedNode1 = vm.addr(701);
        address trustedNode2 = vm.addr(702);
        address trustedNode3 = vm.addr(703);
        address trustedNode4 = vm.addr(704);
        address trustedNode5 = vm.addr(705);

        vm.prank(staderManager);
        staderOracle.addTrustedNode(trustedNode1);

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InsufficientTrustedNodes.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        vm.startPrank(staderManager);
        staderOracle.addTrustedNode(trustedNode2);
        staderOracle.addTrustedNode(trustedNode3);
        staderOracle.addTrustedNode(trustedNode4);
        staderOracle.addTrustedNode(trustedNode5);
        vm.stopPrank();

        // lets pause and then try
        vm.prank(staderManager);
        staderOracle.pause();

        vm.prank(trustedNode1);
        vm.expectRevert('Pausable: paused');
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // now lets unpause and then try
        vm.prank(staderAdmin);
        staderOracle.unpause();

        assertEq(block.number, 1);
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        vm.mockCall(
            address(poolUtils),
            abi.encodeWithSelector(IPoolUtils.getSocializingPoolAddress.selector),
            abi.encode(address(permissionlessSP))
        );

        vm.prank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(100);

        uint256 reportingBlockNumber = staderOracle.getMerkleRootReportableBlockByPoolId(1);
        rewardsData.reportingBlockNumber = reportingBlockNumber;

        // current block num = 1, reportingBlockNum = 100
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        vm.roll(reportingBlockNumber);

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // wait reportBlock to pass
        vm.roll(reportingBlockNumber + 1);
        rewardsData.reportingBlockNumber = 45; // try subimitting a wrong reportingBlock

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // trying to submit for future index
        rewardsData.reportingBlockNumber = reportingBlockNumber; // correct reporting blockNumber
        rewardsData.index = 6; // wrong index

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidMerkleRootIndex.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        rewardsData.index = staderOracle.getCurrentRewardsIndexByPoolId(1); // correct index 1

        // successful submission
        vm.prank(trustedNode1);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // tries to submit again
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // let's suppose it submitted some wrong data earlier
        // oracle can submit again with modified data

        rewardsData.operatorETHRewards = 1111;
        vm.prank(trustedNode1);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        vm.prank(trustedNode2);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // consensus submission
        vm.prank(trustedNode3);
        vm.expectRevert(ISocializingPool.InsufficientETHRewards.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // send eth rewards to SocializingPool
        uint256 totalEthRewards = rewardsData.userETHRewards +
            rewardsData.protocolETHRewards +
            rewardsData.operatorETHRewards;
        vm.deal(address(permissionlessSP), totalEthRewards);

        vm.prank(trustedNode3);
        vm.expectRevert(ISocializingPool.InsufficientSDRewards.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // send SD tokens to socializingPool
        staderToken.transfer(address(permissionlessSP), rewardsData.operatorSDRewards);

        // setup sspm and treasury address
        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        assertEq(staderToken.balanceOf(address(permissionlessSP)), rewardsData.operatorSDRewards);
        assertEq(address(permissionlessSP).balance, totalEthRewards);
        assertEq(treasury.balance, 0);
        assertEq(address(sspm).balance, 0);
        assertFalse(permissionlessSP.handledRewards(rewardsData.index));
        assertEq(permissionlessSP.totalOperatorETHRewardsRemaining(), 0);
        assertEq(permissionlessSP.totalOperatorSDRewardsRemaining(), 0);
        assertEq(permissionlessSP.getCurrentRewardsIndex(), 1);
        assertEq(staderOracle.getCurrentRewardsIndexByPoolId(1), 1);

        vm.prank(trustedNode3);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        assertTrue(permissionlessSP.handledRewards(rewardsData.index));
        assertEq(staderToken.balanceOf(address(permissionlessSP)), rewardsData.operatorSDRewards);
        assertEq(address(permissionlessSP).balance, rewardsData.operatorETHRewards);
        assertEq(address(treasury).balance, rewardsData.protocolETHRewards);
        assertEq(address(sspm).balance, rewardsData.userETHRewards);

        assertEq(permissionlessSP.totalOperatorETHRewardsRemaining(), rewardsData.operatorETHRewards);
        assertEq(permissionlessSP.totalOperatorSDRewardsRemaining(), rewardsData.operatorSDRewards);
        assertEq(permissionlessSP.getCurrentRewardsIndex(), 2);
        assertEq(staderOracle.getCurrentRewardsIndexByPoolId(1), 2);

        // index = 1, has been completed till now

        // lets check if rewardDetails worksfine
        (uint256 startBlock, uint256 endBlock) = permissionlessSP.getRewardCycleDetails(1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 100);

        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(2);
        assertEq(startBlock, 101);
        assertEq(endBlock, 200);

        vm.expectRevert(ISocializingPool.FutureCycleIndex.selector);
        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(3);

        // lets change cycle duration and check
        vm.prank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(200);

        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 100);

        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(2);
        assertEq(startBlock, 101);
        assertEq(endBlock, 300);

        vm.expectRevert(ISocializingPool.FutureCycleIndex.selector);
        (startBlock, endBlock) = permissionlessSP.getRewardCycleDetails(3);

        // lets change cycle duration back to 100
        vm.prank(staderManager);
        staderConfig.updateSocializingPoolCycleDuration(100);

        // // lets try submitting index = 3;

        rewardsData.index = 3;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // lets update the reporting block number
        reportingBlockNumber = staderOracle.getMerkleRootReportableBlockByPoolId(1);
        assertEq(reportingBlockNumber, 200); // reporting blocknumber has been updated to 2nd cycle reporting block num
        rewardsData.reportingBlockNumber = reportingBlockNumber;

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // lets wait for reporting block to pass
        vm.roll(reportingBlockNumber + 1);

        // even then unable to submit a submit a wrong index
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidMerkleRootIndex.selector);
        staderOracle.submitSocializingRewardsMerkleRoot(rewardsData);

        // lets try claiming the 1st cycle rewards

        uint256[] memory indexArray = new uint256[](1);
        indexArray[0] = 1;

        uint256[] memory sdAmountArray = new uint256[](1);
        sdAmountArray[0] = 4000;

        uint256[] memory ethAmountArray = new uint256[](1);
        ethAmountArray[0] = 1000;

        bytes32[][] memory proofArray = new bytes32[][](1);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0xc63b6c7af6a005251da7f3523fd327871a0bf7159fd8688e0d139c3c362ea495;
        proofArray[0] = proof;

        address operator1 = address(500);
        address opRewardAddr1 = vm.addr(4);
        vm.mockCall(
            address(poolUtils.nodeRegistry()),
            abi.encodeWithSelector(INodeRegistry.getOperatorRewardAddress.selector),
            abi.encode(opRewardAddr1)
        );

        assertEq(staderToken.balanceOf(opRewardAddr1), 0);
        assertEq(opRewardAddr1.balance, 0);

        vm.prank(operator1);
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        assertEq(staderToken.balanceOf(opRewardAddr1), 4000);
        assertEq(opRewardAddr1.balance, 1000);

        vm.prank(operator1);
        vm.expectRevert(abi.encodeWithSelector(ISocializingPool.RewardAlreadyClaimed.selector, operator1, 1));
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        indexArray[0] = 0;

        vm.prank(operator1);
        vm.expectRevert(ISocializingPool.InvalidCycleIndex.selector);
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        sdAmountArray[0] = 0;
        ethAmountArray[0] = 0;

        vm.prank(operator1);
        vm.expectRevert(ISocializingPool.InvalidAmount.selector);
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        address operator2 = address(501);
        address opRewardAddr2 = vm.addr(5);
        vm.mockCall(
            address(poolUtils.nodeRegistry()),
            abi.encodeWithSelector(INodeRegistry.getOperatorRewardAddress.selector),
            abi.encode(opRewardAddr2)
        );

        // lets pause and then try
        vm.prank(staderManager);
        permissionlessSP.pause();

        vm.prank(operator2);
        vm.expectRevert('Pausable: paused');
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        // now lets unpause and then try
        vm.prank(staderAdmin);
        permissionlessSP.unpause();

        indexArray[0] = 1;
        sdAmountArray[0] = 12;
        ethAmountArray[0] = 13;

        vm.prank(operator2);
        vm.expectRevert(abi.encodeWithSelector(ISocializingPool.InvalidProof.selector, 1, operator2));
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        sdAmountArray[0] = 444;
        ethAmountArray[0] = 111;
        vm.prank(operator2);
        vm.expectRevert(abi.encodeWithSelector(ISocializingPool.InvalidProof.selector, 1, operator2));
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        proof[0] = 0x3232ed97e5a4e4635f86ad34f4a7598900161d3730083b5759651edfeef92f7e;

        assertEq(staderToken.balanceOf(opRewardAddr2), 0);
        assertEq(opRewardAddr2.balance, 0);

        vm.prank(operator2);
        permissionlessSP.claim(indexArray, sdAmountArray, ethAmountArray, proofArray);

        assertEq(staderToken.balanceOf(opRewardAddr2), 444);
        assertEq(opRewardAddr2.balance, 111);
    }

    function test_updateStaderConfig() public {
        assertEq(address(permissionlessSP.staderConfig()), address(staderConfig));
        assertEq(address(staderOracle.staderConfig()), address(staderConfig));

        // not staderAdmin
        vm.expectRevert();
        permissionlessSP.updateStaderConfig(vm.addr(203));
        vm.expectRevert();
        staderOracle.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        permissionlessSP.updateStaderConfig(vm.addr(203));
        vm.prank(staderAdmin);
        staderOracle.updateStaderConfig(vm.addr(203));

        assertEq(address(permissionlessSP.staderConfig()), vm.addr(203));
        assertEq(address(staderOracle.staderConfig()), vm.addr(203));
    }

    function test_receive() public {
        uint256 amount = 5 ether;
        address randomEOA = vm.addr(762837);

        assertEq(address(permissionlessSP).balance, 0);
        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        (bool success, ) = payable(permissionlessSP).call{value: amount}('');
        assertTrue(success);
        assertEq(address(permissionlessSP).balance, amount);
    }
}
