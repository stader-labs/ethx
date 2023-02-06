pragma solidity ^0.8.16;

import './StaderBasePool.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderELRewardVaultFactory.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionLessStakePool is StaderBasePool, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    uint256 public permissionLessOperatorIndex;
    uint256 public standByPermissionLessValidators;
    address withdrawVaultOwner;
    address permissionLessNOsMEVVault;
    IDepositContract public ethValidatorDeposit;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;
    IStaderELRewardVaultFactory public rewardVaultFactory;

    bytes32 public constant STADER_PERMISSION_LESS_POOL_ADMIN = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN');
    bytes32 public constant PERMISSION_LESS_OPERATOR = keccak256('PERMISSION_LESS_OPERATOR');
    bytes32 public constant PERMISSION_LESS_POOL = keccak256('PERMISSION_LESS_POOL');

    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(
        address _ethValidatorDeposit,
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _rewardVaultFactory,
        address _staderPermissionLessPoolAdmin,
        address _permissionLessNOsMEVVault
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_rewardVaultFactory)
        checkZeroAddress(_staderPermissionLessPoolAdmin)
        checkZeroAddress(_permissionLessNOsMEVVault)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        rewardVaultFactory = IStaderELRewardVaultFactory(_rewardVaultFactory);
        withdrawVaultOwner = _staderPermissionLessPoolAdmin; //make it a generic multisig owner across all contract
        permissionLessNOsMEVVault = _permissionLessNOsMEVVault;
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
    function depositEthToDepositContract() external payable onlyRole(STADER_PERMISSION_LESS_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        require(standByPermissionLessValidators > 0, 'stand by permissionLess validator not available');
        uint256 depositCount = address(this).balance / DEPOSIT_SIZE;
        depositCount = depositCount > standByPermissionLessValidators ? standByPermissionLessValidators : depositCount;
        standByPermissionLessValidators -= depositCount;
        (uint256[] memory selectedOperatorIds, uint256 updatedOperatorIndex) = staderOperatorRegistry.selectOperators(
            depositCount,
            permissionLessOperatorIndex,
            PERMISSION_LESS_POOL
        );
        permissionLessOperatorIndex = updatedOperatorIndex;
        uint256 counter = 0;
        while (counter < depositCount) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexForOperatorId(
                PERMISSION_LESS_POOL,
                selectedOperatorIds[counter]
            );
            require(validatorIndex != type(uint256).max, 'permissionLess validator not available');
            (
                ,
                ,
                bytes memory pubKey,
                bytes memory signature,
                bytes memory withdrawCred,
                bytes32 depositDataRoot,
                ,
                uint256 operatorId,
                ,

            ) = staderValidatorRegistry.validatorRegistry(validatorIndex);

            //slither-disable-next-line arbitrary-send-eth
            ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCred, signature, depositDataRoot);
            staderValidatorRegistry.incrementRegisteredValidatorCount(pubKey);
            staderOperatorRegistry.incrementActiveValidatorCount(operatorId);
            emit DepositToDepositContract(pubKey);
            counter++;
        }
    }

    /**
     * @notice onboard a permissioned node operator
     *
     */
    function onboardPermissionLessNodeOperator(
        bool _mevOptIn,
        address _operatorRewardAddress,
        bytes32 _nodeDistributorSalt,
        string calldata _operatorName,
        uint256 _operatorId
    ) external checkZeroAddress(_operatorRewardAddress) returns (address) {
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        require(operatorIndex != type(uint256).max, 'operatorAlreadyOnboarded');
        address mevFeeRecipientAddress;
        if (!_mevOptIn) {
            mevFeeRecipientAddress = rewardVaultFactory.deployNodeDistributor(
                _nodeDistributorSalt,
                payable(_operatorRewardAddress)
            );
        } else mevFeeRecipientAddress = permissionLessNOsMEVVault;

        staderOperatorRegistry.addToOperatorRegistry(
            _mevOptIn,
            mevFeeRecipientAddress,
            _operatorRewardAddress,
            PERMISSION_LESS_POOL,
            _operatorName,
            _operatorId,
            1,
            0
        );
        return mevFeeRecipientAddress;
    }

    function addValidatorKeys(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        bytes32 _withdrawVaultSalt,
        uint256 _operatorId
    ) external payable onlyRole(PERMISSION_LESS_OPERATOR) {
        require(msg.value == 4 ether, 'invalid collateral');
        require(
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        require(operatorIndex == type(uint256).max, 'operatorNotOnboarded');

        staderOperatorRegistry.incrementValidatorCount(_operatorId);

        address withdrawVault = rewardVaultFactory.deployWithdrawVault(_withdrawVaultSalt, payable(withdrawVaultOwner));
        bytes memory withdrawCredential = rewardVaultFactory.getValidatorWithdrawCredential(withdrawVault);
        _validateKeys(_validatorPubkey, withdrawCredential, _validatorSignature, _depositDataRoot);
        staderValidatorRegistry.addToValidatorRegistry(
            _validatorPubkey,
            _validatorSignature,
            withdrawCredential,
            _depositDataRoot,
            PERMISSION_LESS_POOL,
            _operatorId,
            msg.value
        );
        standByPermissionLessValidators++;
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
