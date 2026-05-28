// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Test } from "forge-std/Test.sol";

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/SocializingPool.sol";

import "../mocks/SDCollateralMock.sol";
import "../mocks/StaderTokenMock.sol";
import "../mocks/StaderOracleMock.sol";
import "../mocks/StakePoolManagerMock.sol";

import { ISocializingPool, RewardsData } from "../../contracts/interfaces/ISocializingPool.sol";

contract SocializingPoolTest is Test {
    event SetCustodyDelay(uint256 sweepToCustodyTimestamp);
    event SweptToCustody(address asset, address custody, uint256 amount);

    address staderAdmin;
    address staderManager;
    address staderTreasury;

    StaderConfig staderConfig;
    SocializingPool socializingPool;
    StaderTokenMock staderToken;
    StaderOracleMock staderOracle;
    SDCollateralMock sdCollateral;
    StakePoolManagerMock stakePoolManager;

    function setUp() public {
        vm.clearMockedCalls();
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        staderTreasury = vm.addr(105);

        staderToken = new StaderTokenMock();
        staderOracle = new StaderOracleMock();
        sdCollateral = new SDCollateralMock();
        stakePoolManager = new StakePoolManagerMock();

        address ethDepositAddr = vm.addr(102);
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        SocializingPool sociImpl = new SocializingPool();
        TransparentUpgradeableProxy sociProxy = new TransparentUpgradeableProxy(address(sociImpl), address(admin), "");
        socializingPool = SocializingPool(payable(address(sociProxy)));
        socializingPool.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        staderConfig.updateStaderOracle(address(staderOracle));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateStakePoolManager(address(stakePoolManager));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(staderTreasury);
    }

    function test_Initialize() public {
        assertEq(address(socializingPool.staderConfig()), address(staderConfig));
        assertEq(socializingPool.totalOperatorETHRewardsRemaining(), 0);
        assertEq(socializingPool.totalOperatorSDRewardsRemaining(), 0);
        assertTrue(socializingPool.hasRole(socializingPool.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertFalse(socializingPool.assetCustodied());
        assertEq(socializingPool.sweepToCustodyTimestamp(), 0);
    }

    // --- Sunset: setCustodyDelay ---

    function test_setCustodyDelay_revertsForNonAdmin() public {
        vm.expectRevert();
        socializingPool.setCustodyDelay(1 days);
    }

    function test_setCustodyDelay_revertsOnZero() public {
        vm.expectRevert(ISocializingPool.ZeroCustodyDelay.selector);
        vm.prank(staderAdmin);
        socializingPool.setCustodyDelay(0);
    }

    function test_setCustodyDelay_setsTimestampAndEmits() public {
        uint256 expected = block.timestamp + 7 days;
        vm.expectEmit(true, true, true, true, address(socializingPool));
        emit SetCustodyDelay(expected);
        vm.prank(staderAdmin);
        socializingPool.setCustodyDelay(7 days);
        assertEq(socializingPool.sweepToCustodyTimestamp(), expected);
    }

    // --- Sunset: sweepToCustody ---

    function _armSPSweep() internal {
        vm.prank(staderAdmin);
        socializingPool.setCustodyDelay(1 days);
        vm.warp(block.timestamp + 1 days + 1);
    }

    function test_sweep_revertsForNonAdmin() public {
        _armSPSweep();
        vm.expectRevert();
        socializingPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_revertsOnZeroCustody() public {
        _armSPSweep();
        vm.expectRevert(ISocializingPool.ZeroAddress.selector);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(0), address(0));
    }

    function test_sweep_revertsBeforeDelay() public {
        vm.prank(staderAdmin);
        socializingPool.setCustodyDelay(1 days);
        vm.expectRevert(ISocializingPool.CustodyDelayNotElapsed.selector);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_revertsOnZeroBalance() public {
        _armSPSweep();
        vm.expectRevert(ISocializingPool.ZeroAmount.selector);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_transfersEthToCustody() public {
        _armSPSweep();
        address custody = vm.addr(701);
        vm.deal(address(socializingPool), 5 ether);

        vm.expectEmit(true, true, true, true, address(socializingPool));
        emit SweptToCustody(address(0), custody, 5 ether);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(0), custody);

        assertEq(custody.balance, 5 ether);
        assertTrue(socializingPool.assetCustodied());
    }

    function test_sweep_transfersSDToCustody() public {
        _armSPSweep();
        address custody = vm.addr(701);
        uint256 amount = 1_000e18;
        staderToken.transfer(address(socializingPool), amount);

        vm.expectEmit(true, true, true, true, address(socializingPool));
        emit SweptToCustody(address(staderToken), custody, amount);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(staderToken), custody);

        assertEq(staderToken.balanceOf(custody), amount);
        assertTrue(socializingPool.assetCustodied());
    }

    // --- Sunset: assetCustodied kill-switch ---

    function _custodyAndSweepSP() internal {
        _armSPSweep();
        vm.deal(address(socializingPool), 1 wei);
        vm.prank(staderAdmin);
        socializingPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_claim_revertsAfterAssetCustodied() public {
        _custodyAndSweepSP();
        uint256[] memory empty = new uint256[](0);
        bytes32[][] memory emptyProof = new bytes32[][](0);
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        socializingPool.claim(empty, empty, empty, emptyProof);
    }

    function test_claimAndDepositSD_revertsAfterAssetCustodied() public {
        _custodyAndSweepSP();
        uint256[] memory empty = new uint256[](0);
        bytes32[][] memory emptyProof = new bytes32[][](0);
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        socializingPool.claimAndDepositSD(empty, empty, empty, emptyProof);
    }

    function test_maxApproveSD_revertsAfterAssetCustodied() public {
        _custodyAndSweepSP();
        vm.expectRevert(ISocializingPool.AssetCustodied.selector);
        vm.prank(staderManager);
        socializingPool.maxApproveSD();
    }
}
