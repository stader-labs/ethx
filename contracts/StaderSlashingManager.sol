pragma solidity ^0.8.16;

import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderSlashingManager.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderSlashingManager is IStaderSlashingManager, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;
    uint256 public bondEthThreshold;
    uint256 public penaltyThreshold = 3;

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

    function updateMisbehavePenaltyScore(bytes[] calldata _pubKeys) external override onlyRole(STADER_DAO) {
        for (uint256 index; index < _pubKeys.length; index++) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexByPublicKey(_pubKeys[index]);
            require(validatorIndex != type(uint256).max, 'validator not available');
            (, , , , , , , , , uint256 penaltyCount) = staderValidatorRegistry.validatorRegistry(validatorIndex);
            penaltyCount++;
            staderValidatorRegistry.increasePenaltyCount(validatorIndex);
            if (penaltyCount >= penaltyThreshold) {
                staderValidatorRegistry.markValidatorReadyForWithdrawal(validatorIndex);
            }
        }
    }

    function updateBondEthWithPenalties(bytes[] calldata _pubKeys, uint256[] calldata _validatorPenalties)
        external
        override
        onlyRole(STADER_DAO)
    {
        require(_pubKeys.length == _validatorPenalties.length, 'incorrect validatorPenalties data');
        for (uint256 index; index < _pubKeys.length; index++) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexByPublicKey(_pubKeys[index]);
            require(validatorIndex != type(uint256).max, 'validator not available');
            (, , , , , , , , uint256 bondEth, ) = staderValidatorRegistry.validatorRegistry(validatorIndex);
            bondEth = bondEth >= _validatorPenalties[index] ? bondEth - _validatorPenalties[index] : 0;
            staderValidatorRegistry.updateBondEth(validatorIndex, bondEth);
            if (bondEth <= bondEthThreshold) {
                staderValidatorRegistry.markValidatorReadyForWithdrawal(validatorIndex);
            }
        }
    }

    function processWithdrawnValidators(bytes[] calldata _pubKeys, uint256[] calldata _nodeShare)
        external
        override
        onlyRole(STADER_DAO)
    {
        require(_pubKeys.length == _nodeShare.length, 'incorrect slashingPenalty data');
        for (uint256 index; index < _pubKeys.length; index++) {
            uint256 validatorIndex = staderValidatorRegistry.getValidatorIndexByPublicKey(_pubKeys[index]);
            require(validatorIndex != type(uint256).max, 'validator not available');
            (, , , , , , , uint256 operatorId, , ) = staderValidatorRegistry.validatorRegistry(validatorIndex);

            address nodeOperator = staderOperatorRegistry.operatorByOperatorId(operatorId);
            (, , , address operatorRewardAddress, , , , ) = staderOperatorRegistry.operatorRegistry(nodeOperator);
            if (_nodeShare[index] > 0) {
                //permission less operator
                //write withdraw balance logic for node operator
            }
            // staderValidatorRegistry.handleWithdrawnValidators(_pubKeys[index]);
            // staderOperatorRegistry.reduceOperatorValidatorsCount(operatorId);
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

    /**
     * @dev update bond Eth threshold to trigger voluntary exit
     * @param _newBondEthThreshold new bondEth threshold limit
     */
    function updateBondEthThreshold(uint256 _newBondEthThreshold) external override onlyRole(STADER_DAO) {
        bondEthThreshold = _newBondEthThreshold;
    }

    /**
     * @dev update penalty threshold to trigger voluntary exit
     * @param _newPenaltyThreshold new penalty threshold limit
     */
    function updatePenaltyThreshold(uint256 _newPenaltyThreshold) external override onlyRole(STADER_DAO) {
        penaltyThreshold = _newPenaltyThreshold;
    }
}
