pragma solidity ^0.8.16;

import './ETHxVault.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionLessStakePool is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    ETHxVault public staderVault;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    IDepositContract public ethValidatorDeposit;
    bytes public withdrawCredential;
    IStaderValidatorRegistry public staderValidatorRegistry;

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
        bytes calldata _withdrawCredential,
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
        staderValidatorRegistry = IStaderValidatorRegistry(_validatorRegistry);
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
        uint256 validatorCount = staderValidatorRegistry.validatorCount();
        uint256 registeredValidatorCount = staderValidatorRegistry.registeredValidatorCount();
        require(registeredValidatorCount <= validatorCount, 'not enough validator to register');
        (, bytes memory pubKey, bytes memory signature, bytes32 depositDataRoot, , , , , ) = staderValidatorRegistry
            .validatorRegistry(registeredValidatorCount);
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCredential, signature, depositDataRoot);
        staderValidatorRegistry.incrementRegisteredValidatorCount();
        emit DepositToDepositContract(pubKey);
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
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        staderValidatorRegistry.addToValidatorRegistry(
            false,
            _validatorPubkey,
            _validatorSignature,
            _depositDataRoot,
            'staderPermissionLessPool',
            _nodeName,
            _nodeRewardAddress,
            _nodeFees,
            msg.value
        );
    }
}
