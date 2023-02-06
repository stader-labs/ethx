// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStaderOperatorRegistry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderOperatorRegistry is IStaderOperatorRegistry, Initializable, AccessControlUpgradeable {
    uint256 public override operatorCount;

    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Operator {
        bool optedForSocializingPool;
        address mevRewardAddress;
        address payable operatorRewardAddress; //Eth1 address of node for reward
        bytes32 staderPoolType; // pool to which the operator belong
        string operatorName; // name of the operator
        uint256 operatorId; // unique ID given by stader network
        uint256 validatorCount; // validator registered with stader
        uint256 activeValidatorCount; // active validator on beacon chain
    }
    mapping(uint256 => Operator) public override operatorRegistry;
    mapping(uint256 => uint256) public override operatorRegistryIndexByOperatorId;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        bool _optedForSocializingPool,
        address _mevRewardAddress,
        address _operatorRewardAddress,
        bytes32 _staderPoolType,
        string memory _operatorName,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _activeValidatorCount
    ) external override onlyRole(STADER_NETWORK_POOL) {
        Operator storage _operatorRegistry = operatorRegistry[operatorCount];
        _operatorRegistry.optedForSocializingPool = _optedForSocializingPool;
        _operatorRegistry.mevRewardAddress = _mevRewardAddress;
        _operatorRegistry.operatorRewardAddress = payable(_operatorRewardAddress);
        _operatorRegistry.operatorId = _operatorId;
        _operatorRegistry.operatorName = _operatorName;
        _operatorRegistry.staderPoolType = _staderPoolType;
        _operatorRegistry.validatorCount = _validatorCount;
        _operatorRegistry.activeValidatorCount = _activeValidatorCount;
        operatorRegistryIndexByOperatorId[_operatorId] = operatorCount;
        operatorCount++;
        emit AddedToOperatorRegistry(_operatorId, operatorCount);
    }

    /**
     * @notice update the validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function incrementValidatorCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getOperatorIndexById(_operatorId);
        require(index != type(uint256).max, 'invalid operatorId');
        operatorRegistry[index].validatorCount++;
        emit IncrementedValidatorCount(operatorRegistry[index].operatorId, operatorRegistry[index].validatorCount);
    }

    /**
     * @notice update the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function incrementActiveValidatorCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getOperatorIndexById(_operatorId);
        require(index != type(uint256).max, 'invalid operatorId');
        operatorRegistry[index].activeValidatorCount++;
        emit IncrementedActiveValidatorCount(
            operatorRegistry[index].operatorId,
            operatorRegistry[index].activeValidatorCount
        );
    }

    /**
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _operatorId operator ID
     */
    function reduceOperatorValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_SLASHING_MANAGER) {
        uint256 index = getOperatorIndexById(_operatorId);
        require(index != type(uint256).max, 'invalid operatorId');
        if (operatorRegistry[index].validatorCount > 0) {
            operatorRegistry[index].validatorCount--;
            operatorRegistry[index].activeValidatorCount--;
            emit ReducedValidatorCount(
                operatorRegistry[index].operatorId,
                operatorRegistry[index].validatorCount,
                operatorRegistry[index].activeValidatorCount
            );
        }
    }

    /**
     * @notice pick the next set of operator to register validator
     * @param _requiredOperatorCount number of operator require
     * @param _operatorStartIndex starting index of operatorID to scan registry
     * @param _poolType pool type of next operators
     */
    function selectOperators(
        uint256 _requiredOperatorCount,
        uint256 _operatorStartIndex,
        bytes32 _poolType
    ) external view override returns (uint256[] memory, uint256) {
        uint256 counter;
        uint256[] memory outputOperatorIds = new uint256[](_requiredOperatorCount);
        while (_operatorStartIndex < operatorCount) {
            if (
                operatorRegistry[_operatorStartIndex].staderPoolType == _poolType &&
                operatorRegistry[_operatorStartIndex].validatorCount >
                operatorRegistry[_operatorStartIndex].activeValidatorCount
            ) {
                outputOperatorIds[counter] = (operatorRegistry[_operatorStartIndex].operatorId);
                counter++;
            }
            _operatorStartIndex++;
            if (_operatorStartIndex == operatorCount) {
                _operatorStartIndex = 0;
            }
            if (counter == _requiredOperatorCount) {
                return (outputOperatorIds, _operatorStartIndex);
            }
        }
    }

    /**
     * @notice fetch operator index in registry using operatorId
     * @dev public view method
     * @param _operatorId operator ID
     */
    function getOperatorIndexById(uint256 _operatorId) public view override returns (uint256) {
        uint256 index = operatorRegistryIndexByOperatorId[_operatorId];
        if (_operatorId == operatorRegistry[index].operatorId) return index;
        return type(uint256).max;
    }
}
