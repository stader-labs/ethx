// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderOracle.sol";
import "../../contracts/SocializingPool.sol";
import "../../contracts/StaderConfig.sol";

import "../mocks/StaderTokenMock.sol";
import "../mocks/StakePoolManagerMock.sol";
import "../mocks/PoolUtilsMock.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

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
        vm.clearMockedCalls();
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);
        address operator = address(500);

        staderToken = new StaderTokenMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        StaderOracle oracleImpl = new StaderOracle();
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(admin),
            ""
        );
        staderOracle = StaderOracle(address(oracleProxy));
        staderOracle.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ""
        );
        permissionedSP = SocializingPool(payable(permissionedSPProxy));
        permissionedSP.initialize(staderAdmin, address(staderConfig));

        TransparentUpgradeableProxy permissionlessSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ""
        );
        permissionlessSP = SocializingPool(payable(permissionlessSPProxy));
        permissionlessSP.initialize(staderAdmin, address(staderConfig));

        poolUtils = new PoolUtilsMock(address(staderConfig), operator);

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
            ""
        );
        StaderOracle staderOracle2 = StaderOracle(address(oracleProxy));
        staderOracle2.initialize(staderAdmin, address(staderConfig));

        SocializingPool spImpl = new SocializingPool();
        TransparentUpgradeableProxy permissionedSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(admin),
            ""
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

        // lets update trustedNode cooling period
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        staderOracle.updateTrustedNodeChangeCoolingPeriod(100);

        vm.startPrank(staderManager);
        staderOracle.updateTrustedNodeChangeCoolingPeriod(100);

        vm.expectRevert(IStaderOracle.CooldownNotComplete.selector);
        staderOracle.addTrustedNode(vm.addr(78));

        // wait for 100 blocks
        vm.roll(block.number + 100);
        staderOracle.addTrustedNode(vm.addr(78));
        assertEq(staderOracle.trustedNodesCount(), 1);
        assertTrue(staderOracle.isTrustedNode(vm.addr(78)));

        vm.expectRevert(IStaderOracle.CooldownNotComplete.selector);
        staderOracle.removeTrustedNode(vm.addr(78));

        // wait for 100 blocks
        vm.roll(block.number + 100);
        staderOracle.removeTrustedNode(vm.addr(78));
        assertEq(staderOracle.trustedNodesCount(), 0);
        assertFalse(staderOracle.isTrustedNode(vm.addr(78)));
        vm.stopPrank();
    }

    function test_submitSDPrice() public {
        SDPriceData memory sdPriceData = SDPriceData({ reportingBlockNumber: 1212, sdPriceInETH: 1 });
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
        SDPriceData memory sdPriceData = SDPriceData({ reportingBlockNumber: 1212, sdPriceInETH: 1 });

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
        vm.expectRevert("Pausable: paused");
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
        vm.expectRevert("Pausable: paused");
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
        (bool success, ) = payable(permissionlessSP).call{ value: amount }("");
        assertTrue(success);
        assertEq(address(permissionlessSP).balance, amount);
    }

    function test_submitExchangeRate() public {
        ExchangeRate memory erData = ExchangeRate({
            reportingBlockNumber: 100,
            totalETHBalance: 101,
            totalETHXSupply: 100
        });

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

        // if PORFeed is enabled
        assertFalse(staderOracle.isPORFeedBasedERData());
        vm.prank(staderManager);
        staderOracle.togglePORFeedBasedERData();
        assertTrue(staderOracle.isPORFeedBasedERData());

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidERDataSource.selector);
        staderOracle.submitExchangeRateData(erData);

        vm.prank(staderManager);
        staderOracle.togglePORFeedBasedERData();
        assertFalse(staderOracle.isPORFeedBasedERData());

        assertEq(staderOracle.getERReportableBlock(), 0);
        vm.roll(7100);
        assertEq(staderOracle.getERReportableBlock(), 0);

        erData.reportingBlockNumber = 7105;
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitExchangeRateData(erData);

        vm.roll(7205);
        assertEq(staderOracle.getERReportableBlock(), 7200);
        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitExchangeRateData(erData);

        erData.reportingBlockNumber = 7200;
        vm.prank(trustedNode1);
        staderOracle.submitExchangeRateData(erData);

        vm.prank(trustedNode1);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitExchangeRateData(erData);

        vm.prank(trustedNode2);
        staderOracle.submitExchangeRateData(erData);

        assertFalse(staderOracle.erInspectionMode());

        ExchangeRate memory erDataTemp = staderOracle.getExchangeRate();

        (uint256 reportingBlockNum, uint256 totalEthBalance, uint256 totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(erDataTemp.reportingBlockNumber, 0);
        assertEq(reportingBlockNum, 0);
        assertEq(totalEthBalance, 0);
        assertEq(totalEthxBalance, 0);

        vm.prank(trustedNode3);
        staderOracle.submitExchangeRateData(erData);

        assertFalse(staderOracle.erInspectionMode());

        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 7200);
        assertEq(totalEthBalance, 101);
        assertEq(totalEthxBalance, 100);

        // t4 tries to push after consesus
        vm.prank(trustedNode4);
        staderOracle.submitExchangeRateData(erData);

        // lets try pushing extra-ordinary ER

        erData.reportingBlockNumber = 2 * 7200;
        erData.totalETHXSupply = 100;
        erData.totalETHBalance = 120;

        vm.roll(erData.reportingBlockNumber + 5);
        assertEq(staderOracle.getERReportableBlock(), erData.reportingBlockNumber);

        vm.prank(trustedNode1);
        staderOracle.submitExchangeRateData(erData);

        vm.prank(trustedNode2);
        staderOracle.submitExchangeRateData(erData);

        vm.prank(trustedNode3);
        staderOracle.submitExchangeRateData(erData);

        // moved to inspectionMode and erData not changed
        assertTrue(staderOracle.erInspectionMode());
        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 7200);
        assertEq(totalEthBalance, 101);
        assertEq(totalEthxBalance, 100);

        // if data is wrong, manager can disable inspection mode and wait for new set of data
        vm.prank(staderManager);
        staderOracle.disableERInspectionMode();

        // turned off inspectionMode and erData not changed
        assertFalse(staderOracle.erInspectionMode());
        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 7200);
        assertEq(totalEthBalance, 101);
        assertEq(totalEthxBalance, 100);

        // t4 tries to submit at same reportingBlock
        vm.prank(trustedNode4);
        staderOracle.submitExchangeRateData(erData);

        // consensus again
        // moved to inspectionMode and erData not changed
        assertTrue(staderOracle.erInspectionMode());

        // if anyone else tries to close
        vm.expectRevert(IStaderOracle.CooldownNotComplete.selector);
        staderOracle.closeERInspectionMode();

        // if manager thinks data is correct, he can accept it
        vm.prank(staderManager);
        staderOracle.closeERInspectionMode();

        // turned off inspectionMode and erData changed
        assertFalse(staderOracle.erInspectionMode());
        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 2 * 7200);
        assertEq(totalEthBalance, 120);
        assertEq(totalEthxBalance, 100);

        // if 7 days passed, anyone can close
        // some wrong data again
        vm.roll(3 * 7200 + 9);
        erData.reportingBlockNumber = staderOracle.getERReportableBlock();
        erData.totalETHBalance = 100;
        erData.totalETHXSupply = 100;

        vm.prank(trustedNode2);
        staderOracle.submitExchangeRateData(erData);
        vm.prank(trustedNode5);
        staderOracle.submitExchangeRateData(erData);
        vm.prank(trustedNode1);
        staderOracle.submitExchangeRateData(erData);

        // moved to inspectionMode and erData not changed
        assertTrue(staderOracle.erInspectionMode());
        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 2 * 7200);
        assertEq(totalEthBalance, 120);
        assertEq(totalEthxBalance, 100);

        // wait for 7 more days
        vm.roll(block.number + 7 * 7200 + 9);

        // now anyone can closeInspection/disable mode
        staderOracle.disableERInspectionMode();
        assertFalse(staderOracle.erInspectionMode());

        vm.prank(trustedNode3);
        staderOracle.submitExchangeRateData(erData);

        assertTrue(staderOracle.erInspectionMode());
        // moved to inspectiodMode again, now they have to wait 7 more days
        vm.expectRevert(IStaderOracle.CooldownNotComplete.selector);
        staderOracle.closeERInspectionMode();

        // wait for 7 more days
        vm.roll(block.number + 7 * 7200 + 4);

        staderOracle.closeERInspectionMode();
        assertFalse(staderOracle.erInspectionMode());

        // turned off inspectionMode and erData changed
        assertFalse(staderOracle.erInspectionMode());
        (reportingBlockNum, totalEthBalance, totalEthxBalance) = staderOracle.exchangeRate();
        assertEq(reportingBlockNum, 3 * 7200);
        assertEq(totalEthBalance, 100);
        assertEq(totalEthxBalance, 100);

        // if someone tries to closeInspectionMode, when it is not in inspectionMode
        vm.expectRevert(IStaderOracle.ERChangeLimitNotCrossed.selector);
        staderOracle.closeERInspectionMode();
    }

    function test_submitValidatorVerificationDetail() public {
        bytes[] memory readyToDepositPubkeys = new bytes[](1);
        readyToDepositPubkeys[0] = "readyToDepositPubkey1";
        bytes[] memory frontRunPubkeys = new bytes[](1);
        frontRunPubkeys[0] = "frontRunPubkey1";
        bytes[] memory invalidSignaturePubkeys = new bytes[](1);
        invalidSignaturePubkeys[0] = "invalidSignaturePubkey1";

        ValidatorVerificationDetail memory vvData = ValidatorVerificationDetail({
            poolId: 1,
            reportingBlockNumber: 1,
            sortedReadyToDepositPubkeys: readyToDepositPubkeys,
            sortedFrontRunPubkeys: frontRunPubkeys,
            sortedInvalidSignaturePubkeys: invalidSignaturePubkeys
        });

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

        vm.roll(7205);
        vvData.reportingBlockNumber = staderOracle.getValidatorVerificationDetailReportableBlock();

        vm.prank(trustedNode1);
        staderOracle.submitValidatorVerificationDetail(vvData);

        vm.prank(trustedNode2);
        staderOracle.submitValidatorVerificationDetail(vvData);

        assertEq(staderOracle.lastReportingBlockNumberForValidatorVerificationDetailByPoolId(1), 0);

        // consensus
        vm.prank(trustedNode3);
        staderOracle.submitValidatorVerificationDetail(vvData);

        assertEq(staderOracle.lastReportingBlockNumberForValidatorVerificationDetailByPoolId(1), 7200);

        // even if t4 submmits, it is accepted
        vm.prank(trustedNode4);
        staderOracle.submitValidatorVerificationDetail(vvData);

        // if it tries again
        vm.prank(trustedNode4);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitValidatorVerificationDetail(vvData);

        // future reporting block num
        vvData.reportingBlockNumber = block.number + 1;

        vm.prank(trustedNode5);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitValidatorVerificationDetail(vvData);

        vm.roll(block.number + 7207);
        vm.prank(trustedNode5);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitValidatorVerificationDetail(vvData);

        // if more time passed
        vm.roll(block.number + 7207);

        // node can submit twice as well
        vvData.reportingBlockNumber = 2 * 7200;
        vm.prank(trustedNode5);
        staderOracle.submitValidatorVerificationDetail(vvData);

        vvData.reportingBlockNumber = 3 * 7200;
        vm.prank(trustedNode5);
        staderOracle.submitValidatorVerificationDetail(vvData);
    }

    function test_submitMissedAttestationPenalties() public {
        bytes[] memory sortedPubkeys = new bytes[](1);
        sortedPubkeys[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";

        MissedAttestationPenaltyData memory mapData = MissedAttestationPenaltyData({
            reportingBlockNumber: 1,
            index: 1,
            sortedPubkeys: sortedPubkeys
        });

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

        vm.roll(50400 + 7);
        assertEq(staderOracle.getMissedAttestationPenaltyReportableBlock(), 50400);

        mapData.reportingBlockNumber = staderOracle.getMissedAttestationPenaltyReportableBlock();

        vm.prank(trustedNode1);
        staderOracle.submitMissedAttestationPenalties(mapData);

        vm.prank(trustedNode2);
        staderOracle.submitMissedAttestationPenalties(mapData);

        bytes32 pubkeyRoot = sha256(abi.encodePacked(sortedPubkeys[0], bytes16(0)));

        assertEq(staderOracle.missedAttestationPenalty(pubkeyRoot), 0);
        assertEq(staderOracle.lastReportedMAPDIndex(), 0);

        vm.prank(trustedNode3);
        staderOracle.submitMissedAttestationPenalties(mapData);

        assertEq(staderOracle.lastReportedMAPDIndex(), 1);
        assertEq(staderOracle.missedAttestationPenalty(pubkeyRoot), 1);

        // t3 tries again
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidMAPDIndex.selector);
        staderOracle.submitMissedAttestationPenalties(mapData);

        // t4 tries after consensus
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidMAPDIndex.selector);
        staderOracle.submitMissedAttestationPenalties(mapData);

        // 2nd index
        vm.roll(block.number + 50409);
        mapData.reportingBlockNumber = 2 * 50400 + 90;

        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitMissedAttestationPenalties(mapData);

        mapData.reportingBlockNumber = 2 * 50400 + 1;
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitMissedAttestationPenalties(mapData);

        mapData.reportingBlockNumber = 2 * 50400;
        mapData.index = 3;
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidMAPDIndex.selector);
        staderOracle.submitMissedAttestationPenalties(mapData);

        mapData.index = 2;
        vm.prank(trustedNode3);
        staderOracle.submitMissedAttestationPenalties(mapData);
    }

    function test_submitWithdrawnValidators() public {
        bytes[] memory sortedPubkeys = new bytes[](1);
        sortedPubkeys[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";

        WithdrawnValidators memory wvData = WithdrawnValidators({
            reportingBlockNumber: 1,
            poolId: 1,
            sortedPubkeys: sortedPubkeys
        });

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

        vm.roll(14400 + 7);
        assertEq(staderOracle.getWithdrawnValidatorReportableBlock(), 14400);

        wvData.reportingBlockNumber = staderOracle.getWithdrawnValidatorReportableBlock();

        vm.prank(trustedNode1);
        staderOracle.submitWithdrawnValidators(wvData);

        vm.prank(trustedNode2);
        staderOracle.submitWithdrawnValidators(wvData);

        assertEq(staderOracle.lastReportingBlockNumberForWithdrawnValidatorsByPoolId(1), 0);

        vm.prank(trustedNode3);
        staderOracle.submitWithdrawnValidators(wvData);

        assertEq(staderOracle.lastReportingBlockNumberForWithdrawnValidatorsByPoolId(1), 14400);

        // t3 tries again
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitWithdrawnValidators(wvData);

        // t4 tries after consensus
        vm.prank(trustedNode4);
        staderOracle.submitWithdrawnValidators(wvData);

        // 2nd round
        vm.roll(block.number + 14400);
        wvData.reportingBlockNumber = 2 * 14400 + 90;

        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitWithdrawnValidators(wvData);

        wvData.reportingBlockNumber = 2 * 14400 + 1;
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitWithdrawnValidators(wvData);

        wvData.reportingBlockNumber = 2 * 14400;
        vm.prank(trustedNode3);
        staderOracle.submitWithdrawnValidators(wvData);
    }

    function test_submitValidatorStats() public {
        ValidatorStats memory valStats = ValidatorStats({
            reportingBlockNumber: 123,
            exitingValidatorsBalance: 100,
            exitedValidatorsBalance: 200,
            slashedValidatorsBalance: 12,
            exitingValidatorsCount: 2,
            exitedValidatorsCount: 3,
            slashedValidatorsCount: 4
        });

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

        vm.roll(7200 + 7);
        assertEq(staderOracle.getValidatorStatsReportableBlock(), 7200);

        valStats.reportingBlockNumber = staderOracle.getValidatorStatsReportableBlock();

        vm.prank(trustedNode1);
        staderOracle.submitValidatorStats(valStats);

        vm.prank(trustedNode2);
        staderOracle.submitValidatorStats(valStats);

        ValidatorStats memory valStatsRes = staderOracle.getValidatorStats();

        assertEq(valStatsRes.reportingBlockNumber, 0);
        assertEq(valStatsRes.exitingValidatorsBalance, 0);
        assertEq(valStatsRes.exitedValidatorsBalance, 0);
        assertEq(valStatsRes.slashedValidatorsBalance, 0);
        assertEq(valStatsRes.exitingValidatorsCount, 0);
        assertEq(valStatsRes.exitedValidatorsCount, 0);
        assertEq(valStatsRes.slashedValidatorsCount, 0);

        vm.prank(trustedNode3);
        staderOracle.submitValidatorStats(valStats);

        valStatsRes = staderOracle.getValidatorStats();

        assertEq(valStatsRes.reportingBlockNumber, 7200);
        assertEq(valStatsRes.exitingValidatorsBalance, 100);
        assertEq(valStatsRes.exitedValidatorsBalance, 200);
        assertEq(valStatsRes.slashedValidatorsBalance, 12);
        assertEq(valStatsRes.exitingValidatorsCount, 2);
        assertEq(valStatsRes.exitedValidatorsCount, 3);
        assertEq(valStatsRes.slashedValidatorsCount, 4);

        // t3 tries again
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.DuplicateSubmissionFromNode.selector);
        staderOracle.submitValidatorStats(valStats);

        // t4 tries after consensus
        vm.prank(trustedNode4);
        staderOracle.submitValidatorStats(valStats);

        // 2nd round
        vm.roll(block.number + 7200);
        valStats.reportingBlockNumber = 2 * 7200 + 90;

        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.ReportingFutureBlockData.selector);
        staderOracle.submitValidatorStats(valStats);

        valStats.reportingBlockNumber = 2 * 7200 + 1;
        vm.prank(trustedNode3);
        vm.expectRevert(IStaderOracle.InvalidReportingBlock.selector);
        staderOracle.submitValidatorStats(valStats);

        valStats.reportingBlockNumber = 2 * 7200;
        vm.prank(trustedNode3);
        staderOracle.submitValidatorStats(valStats);
    }

    function test_safeMode() public {
        assertFalse(staderOracle.safeMode());

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        staderOracle.enableSafeMode();

        vm.prank(staderManager);
        staderOracle.enableSafeMode();
        assertTrue(staderOracle.safeMode());

        vm.expectRevert();
        staderOracle.disableSafeMode();

        vm.prank(staderAdmin);
        staderOracle.disableSafeMode();
        assertFalse(staderOracle.safeMode());
    }

    function test_updateFrequencySetters() public {
        vm.roll(7309);

        assertEq(staderOracle.getSDPriceReportableBlock(), 7200);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        staderOracle.setSDPriceUpdateFrequency(7201);

        vm.prank(staderManager);
        staderOracle.setSDPriceUpdateFrequency(7201);

        assertEq(staderOracle.getSDPriceReportableBlock(), 7201);

        vm.expectRevert(IStaderOracle.FrequencyUnchanged.selector);
        vm.prank(staderManager);
        staderOracle.setSDPriceUpdateFrequency(7201);

        vm.expectRevert(IStaderOracle.ZeroFrequency.selector);
        vm.prank(staderManager);
        staderOracle.setSDPriceUpdateFrequency(0);

        vm.startPrank(staderManager);
        staderOracle.setERUpdateFrequency(7202);
        staderOracle.setMissedAttestationPenaltyUpdateFrequency(7203);
        staderOracle.setValidatorStatsUpdateFrequency(7204);
        staderOracle.setWithdrawnValidatorsUpdateFrequency(7205);
        staderOracle.setValidatorVerificationDetailUpdateFrequency(7206);
        vm.stopPrank();

        assertEq(staderOracle.getSDPriceReportableBlock(), 7201);
        assertEq(staderOracle.getERReportableBlock(), 7202);
        assertEq(staderOracle.getMissedAttestationPenaltyReportableBlock(), 7203);
        assertEq(staderOracle.getValidatorStatsReportableBlock(), 7204);
        assertEq(staderOracle.getWithdrawnValidatorReportableBlock(), 7205);
        assertEq(staderOracle.getValidatorVerificationDetailReportableBlock(), 7206);

        vm.prank(staderManager);
        vm.expectRevert(IStaderOracle.InvalidUpdate.selector);
        staderOracle.setERUpdateFrequency(7200 * 7 + 1);

        vm.prank(staderManager);
        staderOracle.setERUpdateFrequency(7200 * 7 - 1);
    }

    function test_updateERChangeLimit() public {
        vm.expectRevert(UtilLib.CallerNotManager.selector);
        staderOracle.updateERChangeLimit(100);

        vm.prank(staderManager);
        vm.expectRevert(IStaderOracle.ERPermissibleChangeOutofBounds.selector);
        staderOracle.updateERChangeLimit(0);

        vm.prank(staderManager);
        vm.expectRevert(IStaderOracle.ERPermissibleChangeOutofBounds.selector);
        staderOracle.updateERChangeLimit(10001);

        assertEq(staderOracle.erChangeLimit(), 500);

        vm.prank(staderManager);
        staderOracle.updateERChangeLimit(10000);

        assertEq(staderOracle.erChangeLimit(), 10000);

        vm.prank(staderManager);
        staderOracle.updateERChangeLimit(200);

        assertEq(staderOracle.erChangeLimit(), 200);
    }
}
