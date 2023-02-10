pragma solidity ^0.8.16;

import './interfaces/IDepositContract.sol';
import './interfaces/IStaderPoolHelper.sol';
import './library/Address.sol';

import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';

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

    uint256 public maxDepositPerBlock;
    uint256 public constant NODE_BOND = 4 ether;
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    error NotEnoughCapacity();
    error NotSufficientETHToSpinValidator();

    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    
    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _ethValidatorDeposit,
        address _poolHelper,
        uint256 _maxDepositPerBlock
    )
        external
        initializer
    {
        Address.checkZeroAddress(_adminOwner);
        Address.checkZeroAddress(_ethValidatorDeposit);
        Address.checkZeroAddress(_poolHelper);
        __Pausable_init();
        __AccessControl_init_unchained();
        maxDepositPerBlock = _maxDepositPerBlock;
        poolHelper = IStaderPoolHelper(_poolHelper);
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function registerValidatorsOnBeacon() external payable {
        uint256 validatorToSpin = address(this).balance/ 28 ether ;
        if(validatorToSpin ==0) revert NotSufficientETHToSpinValidator();
        validatorToSpin = Math.min(validatorToSpin, maxDepositPerBlock);
            (,,,address operatorRegistry,address validatorRegistry,,uint256 queuedValidatorKeys,,) = poolHelper.staderPool(1);
        if(queuedValidatorKeys < validatorToSpin) revert NotEnoughCapacity();
        IStaderValidatorRegistry(validatorRegistry).transferCollateralToPool(validatorToSpin* NODE_BOND);
        for(uint i = depositQueueStartIndex;i<validatorToSpin+depositQueueStartIndex;i++){
            uint256 validatorId = IStaderValidatorRegistry(validatorRegistry).queueToDeposit(i);
            (,,
            bytes memory pubKey,
            bytes memory signature,
            bytes memory withdrawalAddress,
            bytes32 depositDataRoot,
            uint256 operatorId,,) = IStaderValidatorRegistry(validatorRegistry).validatorRegistry(validatorId);
            ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey,withdrawalAddress,signature,depositDataRoot);

            address nodeOperator = IStaderOperatorRegistry(operatorRegistry).operatorByOperatorId(operatorId);
            
            IStaderValidatorRegistry(validatorRegistry).updateValidatorStatus(pubKey,ValidatorStatus.DEPOSITED);
            IStaderOperatorRegistry(operatorRegistry).reduceQueuedValidatorsCount(nodeOperator);
            IStaderOperatorRegistry(operatorRegistry).incrementActiveValidatorsCount(nodeOperator);
            poolHelper.reduceQueuedValidatorKeys(1);
            poolHelper.incrementActiveValidatorKeys(1);
        }
    }

    function updatePoolHelper(address _poolHelper)
        external
        onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN)
    {
        Address.checkZeroAddress(_poolHelper);
        poolHelper = IStaderPoolHelper(_poolHelper);
    }
}
