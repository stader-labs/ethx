pragma solidity ^0.8.16;

import './types/StaderPoolType.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionLessStakePool is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    IDepositContract public ethValidatorDeposit;
    bytes public withdrawCredential;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant STADER_PERMISSION_LESS_POOL_ADMIN = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN');
    bytes32 public constant PERMISSION_LESS_OPERATOR = keccak256('PERMISSION_LESS_OPERATOR');

    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

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
        address _ethValidatorDeposit,
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _staderPermissionLessPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPermissionLessPoolAdmin)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        withdrawCredential = _withdrawCredential;
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        _grantRole(STADER_PERMISSION_LESS_POOL_ADMIN, _staderPermissionLessPoolAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader managed stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract(uint256[] memory _operatorIds)
        external
        payable
        onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN)
    {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        uint256 depositCount = address(this).balance / DEPOSIT_SIZE;
        require(depositCount == _operatorIds.length, 'Invalid input of operator Ids');
        uint256 counter = 0;
        while (counter < depositCount) {
            uint256 validatorIndex = staderValidatorRegistry.getNextPermissionLessValidator(_operatorIds[counter]);
            require(validatorIndex != type(uint256).max, 'permissionLess validator not available');
            (
                ,
                bytes memory pubKey,
                bytes memory signature,
                bytes32 depositDataRoot,
                ,
                uint256 operatorId,

            ) = staderValidatorRegistry.validatorRegistry(validatorIndex);

            //slither-disable-next-line arbitrary-send-eth
            ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCredential, signature, depositDataRoot);
            staderValidatorRegistry.incrementRegisteredValidatorCount(pubKey);
            staderOperatorRegistry.incrementActiveValidatorCount(operatorId);
            emit DepositToDepositContract(pubKey);
            counter++;
        }
    }

    function nodeDeposit(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        address _operatorRewardAddress,
        string calldata _operatorName,
        uint256 _operatorId
    ) external payable onlyRole(PERMISSION_LESS_OPERATOR) {
        require(msg.value == 4 ether, 'invalid collateral');
        require(
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        if (operatorIndex == type(uint256).max) {
            staderOperatorRegistry.addToOperatorRegistry(
                _operatorRewardAddress,
                _operatorName,
                StaderPoolType.PermissionLess,
                _operatorId,
                1,
                0
            );
        } else {
            staderOperatorRegistry.incrementValidatorCount(_operatorId);
        }
        staderValidatorRegistry.addToValidatorRegistry(
            false,
            _validatorPubkey,
            _validatorSignature,
            _depositDataRoot,
            StaderPoolType.PermissionLess,
            _operatorId,
            msg.value
        );
    }

    /**
     * @notice update the withdraw credential
     * @dev only permission less pool admin can update
     */
    function updateWithdrawCredential(bytes calldata _withdrawCredential)
        external
        onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN)
    {
        withdrawCredential = _withdrawCredential;
    }

    /**
     * @dev update stader validator registry address
     * @param _staderValidatorRegistry staderValidator Registry address
     */
    function updateStaderValidatorRegistry(address _staderValidatorRegistry)
        external
        checkZeroAddress(_staderValidatorRegistry)
        onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN)
    {
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        emit UpdatedStaderValidatorRegistry(address(staderValidatorRegistry));
    }

    /**
     * @dev update stader operator registry address
     * @param _staderOperatorRegistry stader operator Registry address
     */
    function updateStaderOperatorRegistry(address _staderOperatorRegistry)
        external
        checkZeroAddress(_staderOperatorRegistry)
        onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN)
    {
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        emit UpdatedStaderOperatorRegistry(address(staderOperatorRegistry));
    }
}
