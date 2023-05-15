pragma solidity ^0.8.10;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/interfaces/IRatedV1.sol';

import '../../contracts/Penalty.sol';
import '../../contracts/StaderConfig.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract PenaltyTest is Test {
    address staderAdmin;
    address staderManager;
    address rated;

    ProxyAdmin proxyAdmin;
    StaderConfig staderConfig;
    Penalty penaltyContract;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        rated = vm.addr(200);
        address ethDepositAddr = vm.addr(102);

        proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        Penalty penaltyImpl = new Penalty();
        TransparentUpgradeableProxy penaltyProxy = new TransparentUpgradeableProxy(
            address(penaltyImpl),
            address(proxyAdmin),
            ''
        );
        penaltyContract = Penalty(address(penaltyProxy));
        penaltyContract.initialize(staderAdmin, address(staderConfig), rated);

        vm.startPrank(staderAdmin);
        staderConfig.updatePenaltyContract(address(penaltyContract));
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        Penalty penaltyImpl = new Penalty();
        TransparentUpgradeableProxy penaltyProxy = new TransparentUpgradeableProxy(
            address(penaltyImpl),
            address(proxyAdmin),
            ''
        );
        Penalty penaltyContract2 = Penalty(address(penaltyProxy));
        penaltyContract2.initialize(staderAdmin, address(staderConfig), rated);
    }

    function test_initialize() public {
        assertEq(address(penaltyContract.staderConfig()), address(staderConfig));
        assertEq(address(penaltyContract.ratedOracleAddress()), rated);

        assertEq(penaltyContract.mevTheftPenaltyPerStrike(), 1 ether);
        assertEq(penaltyContract.missedAttestationPenaltyPerStrike(), 0.2 ether);
        assertEq(penaltyContract.validatorExitPenaltyThreshold(), 2.5 ether);
        assertTrue(penaltyContract.hasRole(penaltyContract.DEFAULT_ADMIN_ROLE(), staderAdmin));
        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }

    function test_additionalPenaltyAmount(
        address anyone,
        uint256 amount,
        bytes memory pubkey
    ) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        penaltyContract.setAdditionalPenaltyAmount(pubkey, amount);

        vm.startPrank(staderManager);

        if (pubkey.length != 48) {
            vm.expectRevert(UtilLib.InvalidPubkeyLength.selector);
            penaltyContract.setAdditionalPenaltyAmount(pubkey, amount);
            return;
        }
        // NOTE: any string or byte of 48 length is allowed
        assertEq(penaltyContract.getAdditionalPenaltyAmount(pubkey), 0);
        penaltyContract.setAdditionalPenaltyAmount(pubkey, amount);
        assertEq(penaltyContract.getAdditionalPenaltyAmount(pubkey), amount);
    }

    function test_updateMEVTheftPenaltyPerStrike(address anyone, uint256 _mevTheftPenaltyPerStrike) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        penaltyContract.updateMEVTheftPenaltyPerStrike(_mevTheftPenaltyPerStrike);

        assertEq(penaltyContract.mevTheftPenaltyPerStrike(), 1 ether);
        vm.prank(staderManager);
        penaltyContract.updateMEVTheftPenaltyPerStrike(_mevTheftPenaltyPerStrike);
        assertEq(penaltyContract.mevTheftPenaltyPerStrike(), _mevTheftPenaltyPerStrike);
    }

    function test_updateMissedAttestationPenaltyPerStrike(address anyone, uint256 _missedAttestationPenaltyPerStrike)
        public
    {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        penaltyContract.updateMissedAttestationPenaltyPerStrike(_missedAttestationPenaltyPerStrike);

        assertEq(penaltyContract.missedAttestationPenaltyPerStrike(), 0.2 ether);
        vm.prank(staderManager);
        penaltyContract.updateMissedAttestationPenaltyPerStrike(_missedAttestationPenaltyPerStrike);
        assertEq(penaltyContract.missedAttestationPenaltyPerStrike(), _missedAttestationPenaltyPerStrike);
    }

    function test_updateValidatorExitPenaltyThreshold(address anyone, uint256 _validatorExitPenaltyThreshold) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        penaltyContract.updateValidatorExitPenaltyThreshold(_validatorExitPenaltyThreshold);

        assertEq(penaltyContract.validatorExitPenaltyThreshold(), 2.5 ether);
        vm.prank(staderManager);
        penaltyContract.updateValidatorExitPenaltyThreshold(_validatorExitPenaltyThreshold);
        assertEq(penaltyContract.validatorExitPenaltyThreshold(), _validatorExitPenaltyThreshold);
    }

    function test_updateRatedOracleAddress(address anyone, address _ratedOracleAddress) public {
        vm.assume(anyone != address(0) && anyone != address(proxyAdmin) && anyone != staderManager);

        vm.expectRevert(UtilLib.CallerNotManager.selector);
        penaltyContract.updateRatedOracleAddress(_ratedOracleAddress);

        assertEq(penaltyContract.ratedOracleAddress(), rated);
        vm.prank(staderManager);
        vm.expectRevert(UtilLib.ZeroAddress.selector);
        penaltyContract.updateRatedOracleAddress(address(0));

        vm.assume(_ratedOracleAddress != address(0));
        vm.prank(staderManager);
        penaltyContract.updateRatedOracleAddress(_ratedOracleAddress);
        assertEq(penaltyContract.ratedOracleAddress(), _ratedOracleAddress);
    }

    function test_updateStaderConfig(address anyone) public {
        vm.assume(anyone != address(0) && anyone != staderAdmin);
        // not staderAdmin
        vm.prank(anyone);
        vm.expectRevert();
        penaltyContract.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        penaltyContract.updateStaderConfig(vm.addr(203));
        assertEq(address(penaltyContract.staderConfig()), vm.addr(203));
    }

    // function test_updateTotalPenaltyAmount() public {
    //     bytes[] memory pubkeys = new bytes[](1);
    //     pubkeys[0] = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

    //     penaltyContract.updateTotalPenaltyAmount(pubkeys);
    // }
}
