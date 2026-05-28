// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/library/UtilLib.sol";

import "../../contracts/StaderConfig.sol";
import "../../contracts/factory/VaultFactory.sol";
import "../../contracts/PermissionlessPool.sol";

import "../mocks/ETHDepositMock.sol";
import "../mocks/StakePoolManagerMock.sol";
import "../mocks/PermissionlessNodeRegistryMock.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract PermissionlessPoolTest is Test {
    address staderAdmin;
    address staderManager;
    address operator;
    ETHDepositMock ethDepositAddr;

    StaderConfig staderConfig;
    VaultFactory vaultFactory;
    PermissionlessPool permissionlessPool;

    StakePoolManagerMock poolManager;
    PermissionlessNodeRegistryMock nodeRegistry;

    function setUp() public {
        vm.clearMockedCalls();
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        operator = vm.addr(102);

        ethDepositAddr = new ETHDepositMock();
        poolManager = new StakePoolManagerMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ""
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, address(ethDepositAddr));

        VaultFactory vaultImp = new VaultFactory();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vaultImp), address(admin), "");

        vaultFactory = VaultFactory(address(vaultProxy));
        vaultFactory.initialize(staderAdmin, address(staderConfig));

        PermissionlessPool permissionlessPoolImpl = new PermissionlessPool();
        TransparentUpgradeableProxy permissionlessPoolProxy = new TransparentUpgradeableProxy(
            address(permissionlessPoolImpl),
            address(admin),
            ""
        );
        nodeRegistry = new PermissionlessNodeRegistryMock();
        permissionlessPool = PermissionlessPool(payable(address(permissionlessPoolProxy)));
        permissionlessPool.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.updateStakePoolManager(address(poolManager));
        staderConfig.updateVaultFactory(address(vaultFactory));
        staderConfig.updatePermissionlessNodeRegistry(address(nodeRegistry));
        staderConfig.updatePermissionlessSocializingPool(vm.addr(105));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.grantRole(staderConfig.OPERATOR(), operator);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        PermissionlessPool permissionlessPoolImpl = new PermissionlessPool();
        TransparentUpgradeableProxy permissionlessPoolProxy = new TransparentUpgradeableProxy(
            address(permissionlessPoolImpl),
            address(admin),
            ""
        );
        permissionlessPool = PermissionlessPool(payable(address(permissionlessPoolProxy)));
        permissionlessPool.initialize(staderAdmin, address(staderConfig));
    }

    function test_permissionlessPoolInitialize() public {
        assertEq(address(permissionlessPool.staderConfig()), address(staderConfig));
        assertEq(permissionlessPool.protocolFee(), 500);
        assertEq(permissionlessPool.operatorFee(), 500);
        assertEq(permissionlessPool.MAX_COMMISSION_LIMIT_BIPS(), 1500);
        assertEq(permissionlessPool.DEPOSIT_NODE_BOND(), 3 ether);
        assertTrue(permissionlessPool.hasRole(permissionlessPool.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function test_ReceiveFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        payable(permissionlessPool).send(1 ether);
        vm.stopPrank();
    }

    function test_FallbackFunction() public {
        address externalEOA = vm.addr(1000);
        startHoax(externalEOA);
        vm.expectRevert(IStaderPoolBase.UnsupportedOperation.selector);
        payable(permissionlessPool).call{ value: 1 ether }(abi.encodeWithSignature("nonExistentFunction()"));
        vm.stopPrank();
    }

    function test_receiveRemainingCollateralETH(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(this), _amount);
        vm.expectRevert(UtilLib.CallerNotStaderContract.selector);
        permissionlessPool.receiveRemainingCollateralETH{ value: _amount }();
        vm.deal(address(nodeRegistry), _amount);
        vm.prank(address(nodeRegistry));
        permissionlessPool.receiveRemainingCollateralETH{ value: _amount }();
        assertEq(address(permissionlessPool).balance, _amount);
    }

    function test_preDepositOnBeaconChain() public {
        bytes[] memory pubkey = new bytes[](2);
        pubkey[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        pubkey[1] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";

        bytes[] memory preDepositSig = new bytes[](2);
        preDepositSig[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";
        preDepositSig[
            1
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";

        startHoax(address(nodeRegistry), 2 ether);
        permissionlessPool.preDepositOnBeaconChain{ value: 2 ether }(pubkey, preDepositSig, 1, 2);
    }

    function testFail_preDepositOnBeaconChain() public {
        bytes[] memory pubkey = new bytes[](3);
        pubkey[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        pubkey[1] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        pubkey[2] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";

        bytes[] memory preDepositSig = new bytes[](3);
        preDepositSig[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";
        preDepositSig[
            1
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";
        preDepositSig[
            2
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";

        startHoax(address(nodeRegistry), 3 ether);
        permissionlessPool.preDepositOnBeaconChain{ value: 2 ether }(pubkey, preDepositSig, 1, 2);
    }

    function test_preDepositOnBeaconChainWithExtraETH() public {
        bytes[] memory pubkey = new bytes[](2);
        pubkey[0] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        pubkey[1] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";

        bytes[] memory preDepositSig = new bytes[](2);
        preDepositSig[
            0
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";
        preDepositSig[
            1
        ] = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6";

        startHoax(address(nodeRegistry), 10 ether);
        permissionlessPool.preDepositOnBeaconChain{ value: 5 ether }(pubkey, preDepositSig, 1, 2);
        assertEq(address(permissionlessPool).balance, 3 ether);
    }

    function test_StakeUserETHToBeaconChain() public {
        startHoax(address(poolManager));
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(INodeRegistry.validatorRegistry.selector),
            abi.encode(
                ValidatorStatus.INITIALIZED,
                "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336751",
                "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6",
                "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6",
                address(this),
                1,
                150,
                150
            )
        );
        vm.deal(address(nodeRegistry), 50 ether);
        permissionlessPool.stakeUserETHToBeaconChain{ value: 112 ether }();
        assertEq(address(permissionlessPool).balance, 0);
        assertEq(address(nodeRegistry).balance, 38 ether);
        assertEq(address(ethDepositAddr).balance, 124 ether);
    }

    function test_getTotalQueuedValidatorCount() public {
        assertEq(permissionlessPool.getTotalQueuedValidatorCount(), 5);
    }

    function test_getTotalActiveValidatorCount() public {
        assertEq(permissionlessPool.getTotalActiveValidatorCount(), 5);
    }

    function test_getOperatorTotalNonTerminalKeys() public {
        assertEq(permissionlessPool.getOperatorTotalNonTerminalKeys(address(this), 0, 100), 5);
    }

    function test_getSocializingPoolAddress() public {
        assertEq(permissionlessPool.getSocializingPoolAddress(), vm.addr(105));
    }

    function test_getCollateralETH() public {
        assertEq(permissionlessPool.getCollateralETH(), 4 ether);
    }

    function test_getNodeRegistry() public {
        assertEq(permissionlessPool.getNodeRegistry(), address(nodeRegistry));
    }

    function test_isExistingPubkey() public {
        bytes memory pubkey = "0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750";
        assertEq(permissionlessPool.isExistingPubkey(pubkey), true);
    }

    function test_isExistingOperatory() public {
        assertEq(permissionlessPool.isExistingOperator(address(this)), true);
    }

    function test_setCommissionFees(uint64 protocolFee, uint64 operatorFee) public {
        vm.assume(protocolFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(operatorFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.assume(protocolFee + operatorFee <= permissionlessPool.MAX_COMMISSION_LIMIT_BIPS());
        vm.prank(staderManager);
        permissionlessPool.setCommissionFees(protocolFee, operatorFee);
        assertEq(permissionlessPool.protocolFee(), protocolFee);
        assertEq(permissionlessPool.operatorFee(), operatorFee);
    }

    function test_setCommissionFeesWithInvalidInputProtocolFee(uint256 protocolFee) public {
        uint256 operatorFee = permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() / 2;
        vm.assume(
            protocolFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() &&
                protocolFee > permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() - operatorFee
        );
        vm.expectRevert(IStaderPoolBase.InvalidCommission.selector);
        vm.prank(staderManager);
        permissionlessPool.setCommissionFees(protocolFee, operatorFee);
    }

    function test_setCommissionFeesWithInvalidInputOperatorFee(uint256 operatorFee) public {
        uint256 protocolFee = permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() / 2;
        vm.assume(
            operatorFee < permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() &&
                operatorFee > permissionlessPool.MAX_COMMISSION_LIMIT_BIPS() - protocolFee
        );
        vm.expectRevert(IStaderPoolBase.InvalidCommission.selector);
        vm.prank(staderManager);
        permissionlessPool.setCommissionFees(protocolFee, operatorFee);
    }

    function test_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        vm.startPrank(staderAdmin);
        permissionlessPool.updateStaderConfig(newStaderConfig);
        assertEq(address(permissionlessPool.staderConfig()), newStaderConfig);
    }

    function testFail_updateStaderConfig(uint64 _staderConfigSeed) public {
        vm.assume(_staderConfigSeed > 0);
        address newStaderConfig = vm.addr(_staderConfigSeed);
        permissionlessPool.updateStaderConfig(newStaderConfig);
        assertEq(address(permissionlessPool.staderConfig()), newStaderConfig);
    }

    // --- Sunset: setCustodyDelay / sweepToCustody / kill-switch ---

    event SetCustodyDelay(uint256 sweepToCustodyTimestamp);
    event SweptToCustody(address asset, address custody, uint256 amount);

    function test_setCustodyDelay_revertsForNonAdmin() public {
        vm.expectRevert();
        permissionlessPool.setCustodyDelay(1 days);
    }

    function test_setCustodyDelay_revertsOnZero() public {
        vm.expectRevert(PermissionlessPool.ZeroCustodyDelay.selector);
        vm.prank(staderAdmin);
        permissionlessPool.setCustodyDelay(0);
    }

    function test_setCustodyDelay_setsTimestampAndEmits() public {
        uint256 expected = block.timestamp + 7 days;
        vm.expectEmit(true, true, true, true, address(permissionlessPool));
        emit SetCustodyDelay(expected);
        vm.prank(staderAdmin);
        permissionlessPool.setCustodyDelay(7 days);
        assertEq(permissionlessPool.sweepToCustodyTimestamp(), expected);
    }

    function _armPLPSweep() internal {
        vm.prank(staderAdmin);
        permissionlessPool.setCustodyDelay(1 days);
        vm.warp(block.timestamp + 1 days + 1);
    }

    function test_sweep_revertsForNonAdmin() public {
        _armPLPSweep();
        vm.expectRevert();
        permissionlessPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_revertsOnZeroCustody() public {
        _armPLPSweep();
        vm.expectRevert(PermissionlessPool.ZeroAddress.selector);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), address(0));
    }

    function test_sweep_revertsBeforeDelay() public {
        vm.prank(staderAdmin);
        permissionlessPool.setCustodyDelay(1 days);
        vm.expectRevert(PermissionlessPool.CustodyDelayNotElapsed.selector);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_revertsWhenDelayUnset() public {
        vm.expectRevert(PermissionlessPool.CustodyDelayNotElapsed.selector);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_revertsOnZeroBalance() public {
        _armPLPSweep();
        vm.expectRevert(PermissionlessPool.ZeroAmount.selector);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_sweep_transfersEthToCustody() public {
        _armPLPSweep();
        address custody = vm.addr(701);
        vm.deal(address(permissionlessPool), 4 ether);

        vm.expectEmit(true, true, true, true, address(permissionlessPool));
        emit SweptToCustody(address(0), custody, 4 ether);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), custody);

        assertEq(custody.balance, 4 ether);
        assertTrue(permissionlessPool.assetCustodied());
    }

    function _custodyAndSweepPLP() internal {
        _armPLPSweep();
        vm.deal(address(permissionlessPool), 1 wei);
        vm.prank(staderAdmin);
        permissionlessPool.sweepToCustody(address(0), vm.addr(701));
    }

    function test_preDepositOnBeaconChain_revertsAfterAssetCustodied() public {
        _custodyAndSweepPLP();
        bytes[] memory pubkey = new bytes[](1);
        pubkey[0] = "0xdead";
        bytes[] memory sig = new bytes[](1);
        sig[0] = "0xbeef";
        vm.deal(address(nodeRegistry), 1 ether);
        vm.expectRevert(PermissionlessPool.AssetCustodied.selector);
        vm.prank(address(nodeRegistry));
        permissionlessPool.preDepositOnBeaconChain{ value: 1 ether }(pubkey, sig, 1, 0);
    }

    function test_stakeUserETHToBeaconChain_revertsAfterAssetCustodied() public {
        _custodyAndSweepPLP();
        vm.deal(address(poolManager), 32 ether);
        vm.expectRevert(PermissionlessPool.AssetCustodied.selector);
        vm.prank(address(poolManager));
        permissionlessPool.stakeUserETHToBeaconChain{ value: 28 ether }();
    }
}
