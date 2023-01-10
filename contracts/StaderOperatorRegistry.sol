// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './types/StaderPoolType.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderOperatorRegistry is Initializable, AccessControlUpgradeable {
    uint256 public operatorCount;

    bytes32 public constant STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant OPERATOR_REGISTRY_ADMIN = keccak256('OPERATOR_REGISTRY_ADMIN');

    /// @notice event emits after adding a operator to operatorRegistry
    event AddedToOperatorRegistry(uint256 operatorId, uint256 operatorCount);

    /// @notice event emits after increasing validatorCount for an operator
    event IncrementedValidatorCount(uint256 operatorId, uint256 validatorCount);

    /// @notice event emits after increasing activeValidatorCount for an operator
    event IncrementedActiveValidatorCount(uint256 operatorId, uint256 activeValidatorCount);

    struct Operator {
        address operatorRewardAddress; //Eth1 address of node for reward
        string operatorName; // name of the operator
        StaderPoolType staderPoolType; // pool to which the operator belong
        uint256 operatorId; // unique ID given by stader network
        uint256 validatorCount; // validator registered with stader
        uint256 activeValidatorCount; // active validator on beacon chain
    }
    mapping(uint256 => Operator) public operatorRegistry;
    mapping(uint256 => uint256) public operatorIdIndex;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STADER_NETWORK_POOL, msg.sender);
        _grantRole(OPERATOR_REGISTRY_ADMIN, msg.sender);
    }

    /**
     * @notice add a operator to the registry
     * @dev only accept call from stader network pool
     * @param _operatorRewardAddress eth1 wallet of node for reward
     * @param _operatorName node operator name
     * @param _staderPoolType penalty count for misbehaving
     * @param _validatorCount validator registered with stader
     * @param _activeValidatorCount active validator on beacon chain
     */
    function addToOperatorRegistry(
        address _operatorRewardAddress,
        string memory _operatorName,
        StaderPoolType _staderPoolType,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _activeValidatorCount
    ) external onlyRole(STADER_NETWORK_POOL) {
        Operator storage _operatorRegistry = operatorRegistry[operatorCount];
        _operatorRegistry.operatorRewardAddress = _operatorRewardAddress;
        _operatorRegistry.operatorId = _operatorId;
        _operatorRegistry.operatorName = _operatorName;
        _operatorRegistry.staderPoolType = _staderPoolType;
        _operatorRegistry.validatorCount = _validatorCount;
        _operatorRegistry.activeValidatorCount = _activeValidatorCount;
        operatorIdIndex[_operatorId] = operatorCount;
        operatorCount++;
        emit AddedToOperatorRegistry(_operatorId, operatorCount);
    }

    /**
     * @notice update the validator count for a operator
     * @dev only accept call from stader network pools
     */
    function incrementValidatorCount(uint256 operatorId) external onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getOperatorIndexById(operatorId);
        require(index != type(uint256).max, 'invalid operatorId');
        operatorRegistry[index].validatorCount++;
        emit IncrementedValidatorCount(operatorRegistry[index].operatorId, operatorRegistry[index].validatorCount);
    }

    /**
     * @notice update the active validator count for a operator
     * @dev only accept call from stader network pools
     */
    function incrementActiveValidatorCount(uint256 operatorId) external onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getOperatorIndexById(operatorId);
        require(index != type(uint256).max, 'invalid operatorId');
        operatorRegistry[index].activeValidatorCount++;
        emit IncrementedActiveValidatorCount(
            operatorRegistry[index].operatorId,
            operatorRegistry[index].activeValidatorCount
        );
    }

    /**
     * @notice fetch operator index in registry using operatorId
     * @dev public view method
     */
    function getOperatorIndexById(uint256 _operatorId) public view returns (uint256) {
        uint256 index = operatorIdIndex[_operatorId];
        if (_operatorId == operatorRegistry[index].operatorId) return index;
        return type(uint256).max;
    }
}
