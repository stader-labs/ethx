pragma solidity ^0.8.16;

import './ETHxVault.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderPermissionLessValidatorRegistry.sol';
// import './interfaces/IStaderManagedStakePool.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionLessStakePool is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    ETHxVault public staderVault;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    IDepositContract public ethValidatorDeposit;
    uint256 public registeredValidatorCount;
    bytes public withdrawCredential;
    IStaderPermissionLessValidatorRegistry public validatorRegistry;

    bytes32 public constant STADER_PERMISSION_LESS_POOL_ADMIN = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN');
    bytes32 public constant PERMISSION_LESS_OPERATOR = keccak256('PERMISSION_LESS_OPERATOR');

    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(
        bytes _withdrawCredential,
        address _staderVault,
        address _ethValidatorDeposit,
        address _validatorRegistry,
        address _staderPermissionLessPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_staderVault)
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_validatorRegistry)
        checkZeroAddress(_staderPermissionLessPoolAdmin)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        withdrawCredential = _withdrawCredential;
        staderVault = ETHxVault(_staderVault);
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        validatorRegistry = IStaderPermissionLessValidatorRegistry(_validatorRegistry);
        _grantRole(STADER_PERMISSION_LESS_POOL_ADMIN, _staderPermissionLessPoolAdmin);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader managed stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract() external onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        uint256 validatorCount = validatorRegistry.validatorCount();
        require(registeredValidatorCount <= validatorCount, 'not enough validator to register');
        validatorRegistry.validatorRegistry[registeredValidatorCount];
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(
            validatorRegistry.validatorRegistry[registeredValidatorCount].pubKey,
            withdrawCredential,
            validatorRegistry.validatorRegistry[registeredValidatorCount].signature,
            validatorRegistry.validatorRegistry[registeredValidatorCount].depositDataRoot
        );
        registeredValidatorCount++;
        emit DepositToDepositContract(validatorRegistry.validatorRegistry[registeredValidatorCount].pubKey);
    }

    function nodeDeposit(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        address _nodeRewardAddress,
        string calldata _nodeName,
        uint256 _nodeFees
    ) external payable onlyRole(PERMISSION_LESS_OPERATOR) {
        require(msg.value == 4 ether, 'insufficient collateral');
        require(
            validatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        validatorRegistry.addToValidatorRegistry(
            false,
            _validatorPubkey,
            _validatorSignature,
            _depositDataRoot,
            _nodeName,
            _nodeRewardAddress,
            _nodeFees,
            msg.value
        );
    }
}
