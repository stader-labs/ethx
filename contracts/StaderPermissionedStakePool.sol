// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderPermissionedStakePool.sol';
import './interfaces/IStaderOperatorRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionedStakePool is
    IStaderPermissionedStakePool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public permissionedOperatorIndex;
    uint256 public standByPermissionedValidators;
    IDepositContract public ethValidatorDeposit;
    bytes public withdrawCredential;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant STADER_PERMISSIONED_POOL_ADMIN = keccak256('STADER_PERMISSIONED_POOL_ADMIN');
    bytes32 public constant PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');

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
        address _staderPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPoolAdmin)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        withdrawCredential = _withdrawCredential;
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        _grantRole(STADER_PERMISSIONED_POOL_ADMIN, _staderPoolAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader managed stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /**
     * @notice permission pool validator onboarding
     * @dev register the permission pool validators in stader validator registry
     *
     */
    function registerPermissionedValidator(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        address _operatorRewardAddress,
        string calldata _operatorName,
        uint256 _operatorId
    ) external onlyRole(STADER_PERMISSIONED_POOL_ADMIN) {
        require(
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        if (operatorIndex == type(uint256).max) {
            staderOperatorRegistry.addToOperatorRegistry(
                _operatorRewardAddress,
                PERMISSIONED_POOL,
                _operatorName,
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
            PERMISSIONED_POOL,
            _operatorId,
            0
        );
        standByPermissionedValidators++;
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract() external payable onlyRole(STADER_PERMISSIONED_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        require(standByPermissionedValidators > 0, 'stand by permissioned validator not available');
        uint256 depositCount = address(this).balance / DEPOSIT_SIZE;
        depositCount = depositCount > standByPermissionedValidators ? standByPermissionedValidators : depositCount;
        standByPermissionedValidators -= depositCount;
        (uint256[] memory selectedOperatorIds, uint256 updatedOperatorIndex) = staderOperatorRegistry.selectOperators(
            depositCount,
            permissionedOperatorIndex,
            PERMISSIONED_POOL
        );
        permissionedOperatorIndex = updatedOperatorIndex;
        uint256 counter = 0;
        while (counter < depositCount) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexForOperatorId(
                PERMISSIONED_POOL,
                selectedOperatorIds[counter]
            );
            require(validatorIndex != type(uint256).max, 'permissioned validator not available');
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

    /**
     * @notice update the withdraw credential
     * @dev only permission less pool admin can update
     */
    function updateWithdrawCredential(bytes calldata _withdrawCredential)
        external
        onlyRole(STADER_PERMISSIONED_POOL_ADMIN)
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
        onlyRole(STADER_PERMISSIONED_POOL_ADMIN)
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
        onlyRole(STADER_PERMISSIONED_POOL_ADMIN)
    {
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        emit UpdatedStaderOperatorRegistry(address(staderOperatorRegistry));
    }
}
