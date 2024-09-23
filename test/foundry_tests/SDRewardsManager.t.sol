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
        staderConfig.updatePermissionlessSocializingPool(address(permissionlessSP));
        staderConfig.giveCallPermission(address(rewardManager), "addRewardEntry(uint256,uint256)", user1);
        staderConfig.giveCallPermission(address(rewardManager), "approveEntry(uint256,uint256)", user1);
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
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // Only allowed contract can call the addRewardEntry function
        vm.prank(user1);

        // Should emit event for adding entry
        vm.expectEmit(true, false, false, true);
        emit NewRewardEntry(cycleNumber, amount);
        rewardManager.addRewardEntry(cycleNumber, amount);

        // Checking if the entry is correct
        (uint256 storedCycleNumber, uint256 storedAmount, bool isApproved) = rewardManager.rewardEntries(cycleNumber);
        assertEq(storedCycleNumber, cycleNumber);
        assertEq(storedAmount, amount);
        assertEq(isApproved, false);
    }

    function test_addRewardEntry_AccessDenied() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // anyone cannot call the addRewardEntry method
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied(address)", user2));
        rewardManager.addRewardEntry(cycleNumber, amount);
    }

    function test_addRewardEntry_EntryAlreadyRegistered() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // Adding the first entry
        vm.startPrank(user1);
        rewardManager.addRewardEntry(cycleNumber, amount);

        // Attempt to add the same entry again
        vm.expectRevert(abi.encodeWithSignature("EntryAlreadyRegistered(uint256)", cycleNumber));
        rewardManager.addRewardEntry(cycleNumber, amount);
        vm.stopPrank();
    }

    function test_approveEntry() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // Add the entry
        vm.startPrank(user1);
        rewardManager.addRewardEntry(cycleNumber, amount);

        (, uint256 storedAmount, ) = rewardManager.rewardEntries(cycleNumber);
        // Expect the RewardEntryApproved event
        vm.expectEmit(true, false, false, true);
        emit RewardEntryApproved(cycleNumber, storedAmount);
        // Approve the entry
        rewardManager.approveEntry(cycleNumber);
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
        rewardManager.approveEntry(cycleNumber);
    }

    function test_approveEntry_EntryNotFound() public {
        uint256 cycleNumber = 1;

        // Attempt to approve an entry that doesn't exist
        vm.expectRevert(abi.encodeWithSignature("EntryNotFound(uint256)", cycleNumber + 100));
        vm.prank(user1);
        rewardManager.approveEntry(cycleNumber + 100);
    }

    function test_approveEntry_EntryAlreadApproved() public {
        uint256 cycleNumber = 1;
        uint256 amount = 10 ether;

        // Add the entry
        vm.startPrank(user1);
        rewardManager.addRewardEntry(cycleNumber, amount);
        rewardManager.approveEntry(cycleNumber);

        // Attempt to approve the same entry again
        vm.expectRevert(abi.encodeWithSignature("EntryAlreadApproved(uint256)", cycleNumber));
        rewardManager.approveEntry(cycleNumber);
        vm.stopPrank();
    }

    function test_viewLatestEntry() public {
        // Add the entries
        vm.startPrank(user1);
        rewardManager.addRewardEntry(1, 10 ether);
        rewardManager.addRewardEntry(2, 20 ether);
        rewardManager.addRewardEntry(3, 30 ether);
        vm.stopPrank();

        SDRewardManager.SDRewardEntry memory lastestEntry = rewardManager.viewLatestEntry();
        assertEq(lastestEntry.cycleNumber, 3);
        assertEq(lastestEntry.amount, 30 ether);
    }
}
