// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './StaderBasePool.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderPermissionedStakePool.sol';
import './interfaces/IStaderOperatorRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderPermissionedStakePool is
    StaderBasePool,
    IStaderPermissionedStakePool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint256 public permissionedOperatorIndex;
    uint256 public standByPermissionedValidators;
    IDepositContract public ethValidatorDeposit;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant STADER_PERMISSIONED_POOL_ADMIN = keccak256('STADER_PERMISSIONED_POOL_ADMIN');
    bytes32 public constant PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(
        address _ethValidatorDeposit,
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _staderPoolAdmin,
        address _rewardVaultFactory
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPoolAdmin)
        checkZeroAddress(_rewardVaultFactory)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
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

    /// @dev deposit 32 ETH in ethereum deposit contract
    function registerValidatorsOnBeacon() external payable onlyRole(STADER_PERMISSIONED_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        require(standByPermissionedValidators > 0, 'stand by permissioned validator not available');
        uint256 depositCount = address(this).balance / DEPOSIT_SIZE;
        depositCount = depositCount > standByPermissionedValidators ? standByPermissionedValidators : depositCount;
        standByPermissionedValidators -= depositCount;
        (uint256[] memory selectedOperatorIds, uint256 updatedOperatorIndex) = staderOperatorRegistry.selectOperators(
            1,
            depositCount,
            permissionedOperatorIndex
        );
        permissionedOperatorIndex = updatedOperatorIndex;
        uint256 counter = 0;
        while (counter < depositCount) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexForOperatorId(
                1,
                selectedOperatorIds[counter]
            );
            require(validatorIndex != type(uint256).max, 'permissioned validator not available');
            (
                ,
                ,
                bytes memory pubKey,
                bytes memory signature,
                bytes memory withdrawCred,
                uint8 staderPoolId,
                bytes32 depositDataRoot,
                uint256 operatorId,
                ,

            ) = staderValidatorRegistry.validatorRegistry(validatorIndex);

            //slither-disable-next-line arbitrary-send-eth
            ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCred, signature, depositDataRoot);
            staderValidatorRegistry.incrementRegisteredValidatorCount(pubKey);
            staderOperatorRegistry.incrementActiveValidatorsCount(operatorId);
            emit DepositToDepositContract(pubKey);
            counter++;
        }
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
