// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './StaderBasePool.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderPermissionedStakePool.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderELRewardVaultFactory.sol';

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
    address withdrawVaultOwner;
    address permissionedNOsMEVVault;
    IDepositContract public ethValidatorDeposit;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;
    IStaderELRewardVaultFactory public rewardVaultFactory;

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
        address _rewardVaultFactory,
        address _permissionedNOsMEVVault
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPoolAdmin)
        checkZeroAddress(_rewardVaultFactory)
        checkZeroAddress(permissionedNOsMEVVault)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        rewardVaultFactory = IStaderELRewardVaultFactory(_rewardVaultFactory);
        withdrawVaultOwner = _staderPoolAdmin; //make it a generic multisig owner across all contract
        permissionedNOsMEVVault = _permissionedNOsMEVVault;
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
     * @notice onboard a permissioned node operator
     *
     */
    function onboardPermissionedNodeOperator(
        address _operatorRewardAddress,
        string calldata _operatorName,
        uint256 _operatorId
    ) external onlyRole(STADER_PERMISSIONED_POOL_ADMIN) checkZeroAddress(_operatorRewardAddress) returns (address) {
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        require(operatorIndex != type(uint256).max, 'operatorAlreadyOnboarded');
        staderOperatorRegistry.addToOperatorRegistry(
            true,
            permissionedNOsMEVVault,
            _operatorRewardAddress,
            PERMISSIONED_POOL,
            _operatorName,
            _operatorId,
            1,
            0
        );
        return permissionedNOsMEVVault;
    }

    /**
     * @notice permission pool validator onboarding
     * @dev register the permission pool validators in stader validator registry
     *
     */
    function addValidatorKeys(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        bytes32 _withdrawVaultSalt,
        uint256 _operatorId
    ) external onlyRole(STADER_PERMISSIONED_POOL_ADMIN) {
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
            PERMISSIONED_POOL,
            _operatorId,
            0
        );
        standByPermissionedValidators++;
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function registerValidatorsOnBeacon() external payable onlyRole(STADER_PERMISSIONED_POOL_ADMIN) {
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
