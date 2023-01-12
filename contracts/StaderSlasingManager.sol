pragma solidity ^0.8.16;

import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderSlashingManager.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderSlashingManager is IStaderSlashingManager, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant override STADER_DAO = keccak256('STADER_DAO');
    bytes32 public constant override SLASHING_MANAGER_OWNER = keccak256('SLASHING_MANAGER_OWNER');

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    function initialize(
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _slashingManagerOwner
    )
        external
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_slashingManagerOwner)
        initializer
    {
        __AccessControl_init_unchained();
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        _grantRole(SLASHING_MANAGER_OWNER, _slashingManagerOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function processVoluntaryExitValidators(bytes[] calldata _pubKeys, uint256[] calldata _currentBondETH)
        external
        override
        onlyRole(STADER_DAO)
    {
        require(_pubKeys.length == _currentBondETH.length, 'incorrect slashingPenalty data');
        for (uint256 index; index < _pubKeys.length; index++) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexByPublicKey(_pubKeys[index]);
            require(validatorIndex != type(uint256).max, 'validator not available');
            (, , , , , uint256 operatorId, ) = staderValidatorRegistry.validatorRegistry(validatorIndex);
            if (_currentBondETH[index] > 0) {
                //write withdraw balance logic for node operator
            }
            staderValidatorRegistry.handleVoluntaryExitValidators(_pubKeys[index]);
            staderOperatorRegistry.reduceOperatorValidatorsCount(operatorId);
        }
    }

    /**
     * @dev update stader validator registry address
     * @param _staderValidatorRegistry staderValidator Registry address
     */
    function updateStaderValidatorRegistry(address _staderValidatorRegistry)
        external
        override
        checkZeroAddress(_staderValidatorRegistry)
        onlyRole(SLASHING_MANAGER_OWNER)
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
        override
        checkZeroAddress(_staderOperatorRegistry)
        onlyRole(SLASHING_MANAGER_OWNER)
    {
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        emit UpdatedStaderOperatorRegistry(address(staderOperatorRegistry));
    }
}
