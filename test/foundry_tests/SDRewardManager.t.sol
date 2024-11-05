// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/SDRewardManager.sol";
import "../../contracts/StaderConfig.sol";
import "../../contracts/SocializingPool.sol";

import "../mocks/StaderTokenMock.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract SDRewardManagerTest is Test {
    address staderAdmin;
    address staderManager;
    address user1;
    address user2;
    address staderTokenDeployer;
    uint256 latestCycleNumber;

    StaderConfig staderConfig;
    SDRewardManager rewardManager;
    StaderTokenMock staderToken;
    SocializingPool permissionlessSP;

    event NewRewardEntry(uint256 indexed cycleNumber, uint256 amount);
    event RewardEntryApproved(uint256 indexed cycleNumber, uint256 amount);

    function setUp() public {
        staderAdmin = vm.addr(100);
        user1 = vm.addr(101);
        user2 = vm.addr(102);
        staderTokenDeployer = vm.addr(103);
        address ethDepositAddr = vm.addr(104);
        staderManager = vm.addr(105);

        vm.prank(staderTokenDeployer);
        staderToken = new StaderTokenMock();
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        SDRewardManager rewardManagerImpl = new SDRewardManager();
        TransparentUpgradeableProxy rewardManagerProxy = new TransparentUpgradeableProxy(
            address(rewardManagerImpl),
            address(proxyAdmin),
            ""
        );
        rewardManager = SDRewardManager(address(rewardManagerProxy));
        rewardManager.initialize(address(staderConfig));

        SocializingPool spImpl = new SocializingPool();

        TransparentUpgradeableProxy permissionlessSPProxy = new TransparentUpgradeableProxy(
            address(spImpl),
            address(proxyAdmin),
            ""
        );
        permissionlessSP = SocializingPool(payable(permissionlessSPProxy));
        permissionlessSP.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.updatePermissionlessSocializingPool(address(permissionlessSP));
        staderConfig.grantRole(staderConfig.ROLE_SD_REWARD_APPROVER(), user1);
        staderConfig.grantRole(staderConfig.ROLE_SD_REWARD_ENTRY(), user1);
        vm.stopPrank();

        vm.startPrank(staderTokenDeployer);
        IERC20Upgradeable(staderConfig.getStaderToken()).transfer(user1, 100 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        IERC20Upgradeable(staderConfig.getStaderToken()).approve(address(rewardManager), 100 ether);
        vm.stopPrank();
    }

    function test_initialize() public {
        assertEq(address(rewardManager.staderConfig()), address(staderConfig));
        assertEq(staderConfig.getStaderToken(), address(staderToken));
        assertEq(address(permissionlessSP.staderConfig()), address(staderConfig));

        assertTrue(permissionlessSP.hasRole(permissionlessSP.DEFAULT_ADMIN_ROLE(), staderAdmin));

        assertEq(staderConfig.getPermissionlessSocializingPool(), address(permissionlessSP));
    }

    function test_addRewardEntry() public {
        uint256 cycleNumber = 3;
        vm.mockCall(
            address(permissionlessSP),
            abi.encodeWithSelector(ISocializingPool.getCurrentRewardsIndex.selector),
            abi.encode(cycleNumber)
        );
        uint256 amount = 10 ether;

        // Only allowed contract can call the addRewardEntry function
        vm.prank(user1);

        // Should emit event for adding entry
        vm.expectEmit(true, false, false, true);
        emit NewRewardEntry(cycleNumber, amount);
        rewardManager.addRewardEntry(amount);

        // Checking if the entry is correct
        (uint256 storedCycleNumber, uint256 storedAmount, bool isApproved) = rewardManager.rewardEntries(cycleNumber);
        assertEq(storedCycleNumber, cycleNumber);
        assertEq(storedAmount, amount);
        assertEq(isApproved, false);
    }

    function test_addRewardEntry_multipleTimes() public {
        uint256 cycleNumber = 1;
        uint256 amount1 = 10 ether;
        uint256 amount2 = 20 ether;

        // Only allowed contract can call the addRewardEntry function
        vm.startPrank(user1);

        // Adding entry first time
        rewardManager.addRewardEntry(amount1);

        // Adding entry second time
        rewardManager.addRewardEntry(amount2);

        vm.stopPrank();

        // Checking if the entry is correct
        (uint256 storedCycleNumber, uint256 storedAmount, bool isApproved) = rewardManager.rewardEntries(cycleNumber);
        assertEq(storedCycleNumber, cycleNumber);
        assertEq(storedAmount, amount2);
        assertEq(isApproved, false);
    }

    function test_addRewardEntry_AccessDenied() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // anyone cannot call the addRewardEntry method
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied(address)", user2));
        rewardManager.addRewardEntry(amount);
    }

    function test_addRewardEntry_EntryAlreadyApproved() public {
        uint256 cycleNumber = 1;
        uint256 amount1 = 10 ether;
        uint256 amount2 = 20 ether;

        // Only allowed user's can call the addRewardEntry function
        vm.startPrank(user1);

        // Adding entry first time
        rewardManager.addRewardEntry(amount1);

        // Approving Entry
        rewardManager.approveEntry();

        // Adding entry second time
        vm.expectRevert(abi.encodeWithSignature("EntryAlreadyApproved(uint256)", cycleNumber));
        rewardManager.addRewardEntry(amount2);

        vm.stopPrank();
    }

    function test_approveEntry() public {
        uint256 cycleNumber = 19;
        vm.mockCall(
            address(permissionlessSP),
            abi.encodeWithSelector(ISocializingPool.getCurrentRewardsIndex.selector),
            abi.encode(cycleNumber)
        );
        uint256 amount = 10 ether;

        // Add the entry
        vm.startPrank(user1);
        rewardManager.addRewardEntry(amount);

        (, uint256 storedAmount, ) = rewardManager.rewardEntries(cycleNumber);
        // Expect the RewardEntryApproved event
        vm.expectEmit(true, false, false, true);
        emit RewardEntryApproved(cycleNumber, storedAmount);
        // Approve the entry
        rewardManager.approveEntry();
        vm.stopPrank();

        // Check if the entry is approved
        (, , bool isApproved) = rewardManager.rewardEntries(cycleNumber);
        assertTrue(isApproved);
    }

    function test_approveEntry_AccessDenied() public {
        uint256 cycleNumber = 1;

        // anyone cannot call the approveEntry method
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied(address)", user2));
        rewardManager.approveEntry();
    }

    function test_approveEntry_EntryAlreadyApproved() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // Add the entry
        vm.startPrank(user1);
        rewardManager.addRewardEntry(amount);
        rewardManager.approveEntry();

        // Attempt to approve the same entry again
        vm.expectRevert(abi.encodeWithSignature("EntryAlreadyApproved(uint256)", cycleNumber));
        rewardManager.approveEntry();
        vm.stopPrank();
    }

    function test_viewLatestEntry() public {
        // Add the entries
        uint256 cycleNumber = 100;
        vm.mockCall(
            address(permissionlessSP),
            abi.encodeWithSelector(ISocializingPool.getCurrentRewardsIndex.selector),
            abi.encode(cycleNumber)
        );
        vm.startPrank(user1);
        rewardManager.addRewardEntry(30 ether);
        vm.stopPrank();

        SDRewardManager.SDRewardEntry memory lastestEntry = rewardManager.viewLatestEntry();
        assertEq(lastestEntry.cycleNumber, cycleNumber);
        assertEq(lastestEntry.amount, 30 ether);
    }

    function getCurrentCycleNumber() public {
        uint256 cycleNumber = 101;
        vm.mockCall(
            address(permissionlessSP),
            abi.encodeWithSelector(ISocializingPool.getCurrentRewardsIndex.selector),
            abi.encode(cycleNumber)
        );

        uint256 currentCycleStored = rewardManager.getCurrentCycleNumber();
        assertEq(currentCycleStored, cycleNumber);
    }
}
