// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract OperatorRegistryBase is Initializable, ContextUpgradeable {

    error ZeroAddress();
    error InvalidPoolIdInput();
    error OperatorAlreadyOnBoarded();
    error OperatorNotWhitelisted();
    error OperatorNotRegistered();
    error NoInitializedValidatorLeft();
    error NoQueuedValidatorLeft();
    error NoActiveValidatorLeft();

    event OperatorWhitelisted(uint256 whitelistedNOsCount);
    event IncrementedInitializedValidatorsCount(uint256 operatorId, uint256 initializedValidatorCount);
    event ReducedInitializedValidatorsCount(uint256 operatorId, uint256 initializedValidatorCount);
    event IncrementedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event ReducedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event IncrementedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event ReducedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event IncrementedWithdrawnValidatorsCount(uint256 operatorId, uint256 withdrawnValidators);

    address public elRewardSocializePool;
    uint256 public nextOperatorId;

    bytes32 public constant  OPERATOR_REGISTRY_OWNER = keccak256('OPERATOR_REGISTRY_OWNER');
    bytes32 public constant  STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant  STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Operator {
        bool optedForSocializingPool; // operator opted for socializing pool
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        uint256 operatorId; // unique ID given by stader network
        uint256 initializedValidatorCount; //validator whose keys added but not given pre signed msg for withdrawal
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    mapping(address => Operator) public  operatorRegistry;
    mapping(uint256 => address) public  operatorByOperatorId;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function __OperatorRegistryBase_init_(
        address _elRewardSocializePool
    )
        internal
        onlyInitializing
    {

        elRewardSocializePool = _elRewardSocializePool;
        nextOperatorId = 1;
    }

    /**
     * @notice increase the initialized validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function _incrementInitializedValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        operatorRegistry[nodeOperator].initializedValidatorCount++;
        emit IncrementedInitializedValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].initializedValidatorCount
        );
    }

    /**
     * @notice reduce the initialized validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function _reduceInitializedValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        if (operatorRegistry[nodeOperator].initializedValidatorCount == 0) revert NoInitializedValidatorLeft();
        operatorRegistry[nodeOperator].initializedValidatorCount--;
        emit ReducedInitializedValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].initializedValidatorCount
        );
    }

    /**
     * @notice increase the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function _incrementQueuedValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        operatorRegistry[nodeOperator].queuedValidatorCount++;
        emit IncrementedQueuedValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].queuedValidatorCount
        );
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function _reduceQueuedValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        if (operatorRegistry[nodeOperator].queuedValidatorCount == 0) revert NoQueuedValidatorLeft();
        operatorRegistry[nodeOperator].queuedValidatorCount--;
        emit ReducedQueuedValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].queuedValidatorCount
        );
    }

    /**
     * @notice increase the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function _incrementActiveValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        operatorRegistry[nodeOperator].activeValidatorCount++;
        emit IncrementedActiveValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].activeValidatorCount
        );
    }

    /**
     * @notice reduce the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function _reduceActiveValidatorsCount(uint256 _operatorId) internal virtual {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        if (operatorRegistry[nodeOperator].activeValidatorCount == 0) revert NoActiveValidatorLeft();
        operatorRegistry[nodeOperator].activeValidatorCount--;
        emit ReducedActiveValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].activeValidatorCount
        );
    }

    /**
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _operatorId operator ID
     */
    function _incrementWithdrawValidatorsCount(uint256 _operatorId) internal virtual  {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        operatorRegistry[nodeOperator].withdrawnValidatorCount++;
        emit IncrementedWithdrawnValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].withdrawnValidatorCount
        );
    }

    function getOperatorCount() external view  returns (uint256 _operatorCount) {
        _operatorCount = nextOperatorId - 1;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add queued, active and withdrawn validator to get total validators keys
     * @param _nodeOperator node operator address
     */
    function getTotalValidatorKeys(address _nodeOperator) public view returns (uint256 _totalKeys) {
        if (operatorRegistry[_nodeOperator].operatorId == 0) revert OperatorNotRegistered();
        _totalKeys =
            operatorRegistry[_nodeOperator].initializedValidatorCount +
            operatorRegistry[_nodeOperator].queuedValidatorCount +
            operatorRegistry[_nodeOperator].activeValidatorCount +
            operatorRegistry[_nodeOperator].withdrawnValidatorCount;
    }

    function _onboardOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) internal virtual {
        operatorRegistry[msg.sender] = Operator(
            _optInForMevSocialize,
            _operatorName,
            _operatorRewardAddress,
            nextOperatorId,
            0,
            0,
            0,
            0
        );
        operatorByOperatorId[nextOperatorId] = msg.sender;
        nextOperatorId++;
    }
}
