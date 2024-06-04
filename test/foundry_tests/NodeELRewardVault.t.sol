// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/VaultProxy.sol";
import "../../contracts/NodeELRewardVault.sol";
import "../../contracts/OperatorRewardsCollector.sol";
import "../../contracts/factory/VaultFactory.sol";
import { SDCollateral } from "../../contracts/SDCollateral.sol";
import { PoolUtilsMock } from "../mocks/PoolUtilsMock.sol";
import { StakePoolManagerMock } from "../mocks/StakePoolManagerMock.sol";
import { StaderOracleMock } from "../mocks/StaderOracleMock.sol";
import { SDUtilityPoolMock } from "../mocks/SDUtilityPoolMock.sol";

// solhint-disable no-console
contract NodeELRewardVaultTest is Test {
    address private constant OPERATOR_ADDRESSS = address(500);
    address staderAdmin;
    address staderManager;
    address staderTreasury;
    PoolUtilsMock poolUtils;

    uint8 poolId;
    uint256 operatorId;

    StaderConfig staderConfig;
    address payable nodeELCloneAddr;
    OperatorRewardsCollector operatorRC;
    VaultFactory vaultFactory;

    function setUp() public {
        vm.clearMockedCalls();
        poolId = 1;
        operatorId = 1;

        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);
        address sdUtilityPoolMock = vm.addr(103);
        address staderOracleMock = vm.addr(104);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);
        address operator = OPERATOR_ADDRESSS;
        mockStaderOracle(staderOracleMock);
        mockSdUtilityPool(sdUtilityPoolMock, operator);

        OperatorRewardsCollector operatorRCImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRCProxy = new TransparentUpgradeableProxy(
            address(operatorRCImpl),
            address(proxyAdmin),
            ""
        );
        operatorRC = OperatorRewardsCollector(address(operatorRCProxy));
        operatorRC.initialize(staderAdmin, address(staderConfig));

        poolUtils = new PoolUtilsMock(address(staderConfig), operator);
        NodeELRewardVault nodeELRewardVaultImpl = new NodeELRewardVault();

        VaultFactory vfImpl = new VaultFactory();
        TransparentUpgradeableProxy vfProxy = new TransparentUpgradeableProxy(address(vfImpl), address(proxyAdmin), "");
        vaultFactory = VaultFactory(address(vfProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        SDCollateral collateralImpl = new SDCollateral();
        TransparentUpgradeableProxy collateralProxy = new TransparentUpgradeableProxy(
            address(collateralImpl),
            address(staderAdmin),
            ""
        );
        SDCollateral sdCollateral = SDCollateral(address(collateralProxy));
        sdCollateral.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateAdmin(staderAdmin);
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updatePoolUtils(address(poolUtils));
        staderConfig.updateOperatorRewardsCollector(address(operatorRC));
        staderConfig.updateNodeELRewardImplementation(address(nodeELRewardVaultImpl));
        staderConfig.updateSDCollateral(address(sdCollateral));
        staderConfig.updateSDUtilityPool(sdUtilityPoolMock);
        staderConfig.updateStaderOracle(staderOracleMock);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vaultFactory.grantRole(vaultFactory.NODE_REGISTRY_CONTRACT(), address(poolUtils.nodeRegistry()));
        vm.stopPrank();

        vm.prank(address(poolUtils.nodeRegistry()));
        nodeELCloneAddr = payable(vaultFactory.deployNodeELRewardVault(poolId, operatorId));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        OperatorRewardsCollector operatorRCImpl = new OperatorRewardsCollector();
        TransparentUpgradeableProxy operatorRCProxy = new TransparentUpgradeableProxy(
            address(operatorRCImpl),
            address(proxyAdmin),
            ""
        );
        OperatorRewardsCollector operatorRC2 = OperatorRewardsCollector(address(operatorRCProxy));
        operatorRC2.initialize(staderAdmin, address(staderConfig));
    }

    function test_initialise() public {
        assertTrue(VaultProxy(nodeELCloneAddr).isInitialized());

        address randomUser = vm.addr(2342);
        vm.prank(randomUser);
        vm.expectRevert(IVaultProxy.AlreadyInitialized.selector);
        VaultProxy(nodeELCloneAddr).initialise(true, poolId, operatorId, address(staderConfig));

        assertEq(address(VaultProxy(nodeELCloneAddr).staderConfig()), address(staderConfig));
        assertEq(VaultProxy(nodeELCloneAddr).owner(), staderAdmin);
        assertFalse(VaultProxy(nodeELCloneAddr).isValidatorWithdrawalVault());
        assertEq(VaultProxy(nodeELCloneAddr).poolId(), poolId);
        assertEq(VaultProxy(nodeELCloneAddr).id(), operatorId);
    }

    function test_receive(uint256 amount) public {
        address randomEOA = vm.addr(567);

        assertEq(nodeELCloneAddr.balance, 0);

        hoax(randomEOA, amount); // provides amount eth to user and makes it the caller for next call
        (bool success, ) = nodeELCloneAddr.call{ value: amount }("");
        assertTrue(success);

        assertEq(nodeELCloneAddr.balance, amount);
    }

    function testNotEnoughRewardToWithdraw() public {
        assertEq(nodeELCloneAddr.balance, 0);
        vm.expectRevert(INodeELRewardVault.NotEnoughRewardToWithdraw.selector);
        INodeELRewardVault(nodeELCloneAddr).withdraw();
    }

    function testSDUtilityPoolMock() public {
        address sdUtilityPoolMock = staderConfig.getSDUtilityPool();
        address operator = OPERATOR_ADDRESSS;
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(sdUtilityPoolMock);
        UserData memory userData = sdUtilityPool.getUserData(operator);
        assertEq(userData.totalInterestSD, 64);
        assertEq(userData.totalCollateralInEth, 1024);
        assertEq(userData.healthFactor, 1);
        assertEq(userData.lockedEth, 0);
    }

    // NOTE: used uint128 to avoid arithmetic underflow overflow in calculateRewardShare
    function test_withdraw(uint128 rewardEth) public {
        vm.assume(rewardEth > 0);
        console2.log("rewardEth", rewardEth);

        assertEq(nodeELCloneAddr.balance, 0);
        vm.deal(nodeELCloneAddr, rewardEth); // send rewardEth to nodeELRewardVault

        StakePoolManagerMock sspm = new StakePoolManagerMock();
        address treasury = vm.addr(3);
        address opRewardAddr = poolUtils.nodeRegistry().getOperatorRewardAddress(operatorId);
        console2.log("opRewardAddr", opRewardAddr);

        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        address operator = OPERATOR_ADDRESSS;
        assertEq(nodeELCloneAddr.balance, rewardEth);
        assertEq(operatorRC.balances(operator), 0);

        INodeELRewardVault(nodeELCloneAddr).withdraw();

        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = poolUtils.calculateRewardShare(
            1,
            rewardEth
        );

        assertEq(address(sspm).balance, userShare);
        assertEq(address(treasury).balance, protocolShare);
        assertEq(address(opRewardAddr).balance, 0);
        assertEq(address(operatorRC).balance, operatorShare);
        assertEq(operatorRC.balances(operator), operatorShare);

        // claim by operator
        vm.mockCall(
            address(poolUtils.nodeRegistry()),
            abi.encodeWithSelector(INodeRegistry.getOperatorRewardAddress.selector, operator),
            abi.encode(opRewardAddr)
        );

        address sdUtilityPoolMock = staderConfig.getSDUtilityPool();
        vm.mockCall(
            sdUtilityPoolMock,
            abi.encodeWithSelector(ISDUtilityPool.getUserData.selector, operator),
            abi.encode(UserData(64, operatorShare + 1, 1, 0))
        );
        vm.prank(operator);
        operatorRC.claim();

        console2.log("opRewardAddr", opRewardAddr);
        console2.log("operatorShare", operatorShare);
        console2.log("address(opRewardAddr).balance", address(opRewardAddr).balance);

        assertEq(address(opRewardAddr).balance, operatorShare);
        assertEq(operatorRC.balances(operator), 0);
    }

    function test_updateStaderConfig() public {
        vm.expectRevert(IVaultProxy.CallerNotOwner.selector);
        VaultProxy(nodeELCloneAddr).updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        VaultProxy(nodeELCloneAddr).updateStaderConfig(vm.addr(203));
        assertEq(address(VaultProxy(nodeELCloneAddr).staderConfig()), vm.addr(203));
    }

    function test_updateOwner() public {
        assertEq(VaultProxy(nodeELCloneAddr).owner(), staderAdmin);
        vm.prank(staderAdmin);
        staderConfig.updateAdmin(vm.addr(203));
        VaultProxy(nodeELCloneAddr).updateOwner();
        assertEq(VaultProxy(nodeELCloneAddr).owner(), vm.addr(203));
    }

    function mockSdUtilityPool(address sdUtilityPoolMock, address _operator) private {
        emit log_named_address("sdUtilityPoolMock", sdUtilityPoolMock);
        emit log_named_address("operator account", _operator);
        SDUtilityPoolMock implementation = new SDUtilityPoolMock();
        bytes memory mockCode = address(implementation).code;
        vm.etch(sdUtilityPoolMock, mockCode);
        vm.mockCall(
            sdUtilityPoolMock,
            abi.encodeWithSelector(ISDUtilityPool.getOperatorLiquidation.selector, _operator),
            abi.encode(OperatorLiquidation(0, 0, 0, false, false, address(0x0)))
        );
        vm.mockCall(
            sdUtilityPoolMock,
            abi.encodeWithSelector(ISDUtilityPool.getLiquidationThreshold.selector),
            abi.encode(50)
        );
        vm.mockCall(
            sdUtilityPoolMock,
            abi.encodeWithSelector(ISDUtilityPool.getUserData.selector, _operator),
            abi.encode(UserData(64, 1024, 1, 0))
        );
    }

    function mockStaderOracle(address staderOracleMock) private {
        emit log_named_address("staderOracleMock", staderOracleMock);
        StaderOracleMock implementation = new StaderOracleMock();
        bytes memory mockCode = address(implementation).code;
        vm.etch(staderOracleMock, mockCode);
    }
}
