pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/BytesLib.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderPoolHelper.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionLessStakePool is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    IStaderPoolHelper public poolHelper;
    uint256 public depositQueueStartIndex;
    IDepositContract public ethValidatorDeposit;

    bytes32 public constant STADER_PERMISSION_LESS_POOL_ADMIN = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN');
    bytes32 public constant PERMISSION_LESS_OPERATOR = keccak256('PERMISSION_LESS_OPERATOR');
    bytes32 public constant PERMISSION_LESS_POOL = keccak256('PERMISSION_LESS_POOL');

    uint256 public constant NODE_BOND = 4 ether;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;

    error NotEnoughCapacity();
    error NotSufficientETHToSpinValidator();

    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(address _adminOwner, address _ethValidatorDeposit) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_ethValidatorDeposit);
        __Pausable_init();
        __AccessControl_init_unchained();
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    receive() external payable {}

    /// @dev deposit 32 ETH in ethereum deposit contract
    function registerValidatorsOnBeacon() external payable {
        uint256 validatorToSpin = address(this).balance / 28 ether;
        if (validatorToSpin == 0) revert NotSufficientETHToSpinValidator();
        (, , , address operatorRegistry, address validatorRegistry, , uint256 queuedValidatorKeys, , ) = poolHelper
            .staderPool(1);
        if (queuedValidatorKeys < validatorToSpin) revert NotEnoughCapacity();
        IPermissionlessNodeRegistry(validatorRegistry).transferCollateralToPool(validatorToSpin * NODE_BOND);
        for (uint256 i = depositQueueStartIndex; i < validatorToSpin + depositQueueStartIndex; i++) {
            uint256 validatorId = IPermissionlessNodeRegistry(validatorRegistry).queueToDeposit(i);
            (
                ,
                ,
                bytes memory pubKey,
                bytes memory signature,
                bytes memory withdrawalAddress,
                uint256 operatorId,
                ,

            ) = IPermissionlessNodeRegistry(validatorRegistry).validatorRegistry(validatorId);
            //TODO should be add a check if that status should be PRE_DEPOSIT
            bytes32 depositDataRoot = _computeDepositDataRoot(pubKey, signature, withdrawalAddress);
            ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawalAddress, signature, depositDataRoot);

            address nodeOperator = IPermissionlessNodeRegistry(operatorRegistry).operatorByOperatorId(operatorId);

            IPermissionlessNodeRegistry(validatorRegistry).updateValidatorStatus(pubKey, ValidatorStatus.DEPOSITED);
            IPermissionlessNodeRegistry(operatorRegistry).reduceQueuedValidatorsCount(nodeOperator);
            IPermissionlessNodeRegistry(operatorRegistry).incrementActiveValidatorsCount(nodeOperator);
            poolHelper.reduceQueuedValidatorKeys(1);
            poolHelper.incrementActiveValidatorKeys(1);
        }
        depositQueueStartIndex += validatorToSpin;
    }

    function updatePoolHelper(address _poolHelper) external onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN) {
        Address.checkNonZeroAddress(_poolHelper);
        poolHelper = IStaderPoolHelper(_poolHelper);
    }

    function _computeDepositDataRoot(
        bytes memory _pubKey,
        bytes memory _signature,
        bytes memory _withdrawCredential
    ) private pure returns (bytes32) {
        bytes32 publicKeyRoot = sha256(_pad64(_pubKey));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(BytesLib.slice(_signature, 0, 64)),
                sha256(_pad64(BytesLib.slice(_signature, 64, SIGNATURE_LENGTH - 64)))
            )
        );

        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(publicKeyRoot, _withdrawCredential)),
                    sha256(abi.encodePacked(DEPOSIT_SIZE_IN_GWEI_LE64, bytes24(0), signatureRoot))
                )
            );
    }

    /// @dev Padding memory array with zeroes up to 64 bytes on the right
    /// @param _b Memory array of size 32 .. 64
    function _pad64(bytes memory _b) internal pure returns (bytes memory) {
        assert(_b.length >= 32 && _b.length <= 64);
        if (64 == _b.length) return _b;

        bytes memory zero32 = new bytes(32);
        assembly {
            mstore(add(zero32, 0x20), 0)
        }

        if (32 == _b.length) return BytesLib.concat(_b, zero32);
        else return BytesLib.concat(_b, BytesLib.slice(zero32, 0, uint256(64) - _b.length));
    }
}
