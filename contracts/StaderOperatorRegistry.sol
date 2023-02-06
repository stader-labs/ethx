// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStaderPoolHelper.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderRewardContractFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderOperatorRegistry is IStaderOperatorRegistry, Initializable, AccessControlUpgradeable {
    IStaderPoolHelper staderPoolHelper;
    IStaderRewardContractFactory rewardContractFactory;
    address permissionLessSocializePool;
    address permissionedSocializePool;
    uint256 public nextOperatorId;

    bytes32 public constant override OPERATOR_REGISTRY_OWNER = keccak256('OPERATOR_REGISTRY_OWNER');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Operator {
        bool optedForSocializingPool; // operator opted for socializing pool
        uint8 staderPoolId; // pool to which the operator belong
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        uint256 operatorId; // unique ID given by stader network
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    mapping(address => Operator) public override operatorRegistry;
    mapping(address => bool) public override whiteListedPermissionedNOs;
    mapping(uint256 => address) public override operatorByOperatorId;

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
        nextOperatorId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice white list the permissioned node operators
     * @dev update the status of NOs in whitelist mapping, only owner can call
     * @param _nodeOperator wallet of node operator which will interact with contract
     */
    function whiteListPermissionedNOs(address _nodeOperator)
        external
        override
        checkZeroAddress(_nodeOperator)
        onlyRole(OPERATOR_REGISTRY_OWNER)
    {
        whiteListedPermissionedNOs[_nodeOperator] = true;
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, check for whiteListOperator in case of permissionedPool
     * @param _optInForMevSocialize opted in or not to socialize mev and priority fee
     * @param _poolId ID of the stader pool
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address
     */
    function onboardNodeOperator(
        bool _optInForMevSocialize,
        uint8 _poolId,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external override checkZeroAddress(_operatorRewardAddress) returns (address mevFeeRecipientAddress) {
        if (_poolId >= staderPoolHelper.poolTypeCount()) revert InvalidPoolIdInput();
        if (operatorRegistry[msg.sender].operatorId != 0) revert OperatorAlreadyOnBoarded();
        (string memory poolName, address poolAddress, , , ) = staderPoolHelper.staderPool(_poolId);
        mevFeeRecipientAddress = permissionedSocializePool;
        if (keccak256(abi.encodePacked(poolName)) == keccak256(abi.encodePacked('PERMISSIONED'))) {
            if (!whiteListedPermissionedNOs[msg.sender]) revert OperatorNotWhiteListed();
            operatorRegistry[msg.sender] = Operator(
                true,
                _poolId,
                _operatorName,
                _operatorRewardAddress,
                nextOperatorId,
                0,
                0,
                0
            );
            operatorByOperatorId[nextOperatorId] = msg.sender;
            nextOperatorId++;
            return mevFeeRecipientAddress;
        }
        if (whiteListedPermissionedNOs[msg.sender]) revert InvalidPoolIdInput();
        mevFeeRecipientAddress = permissionLessSocializePool;
        if (!_optInForMevSocialize) {
            mevFeeRecipientAddress = rewardContractFactory.deployNodeELRewardVault(
                nextOperatorId,
                payable(_operatorRewardAddress)
            );
        }
        operatorRegistry[msg.sender] = Operator(
            _optInForMevSocialize,
            _poolId,
            _operatorName,
            _operatorRewardAddress,
            nextOperatorId,
            0,
            0,
            0
        );
        operatorByOperatorId[nextOperatorId] = msg.sender;
        nextOperatorId++;
        return mevFeeRecipientAddress;
    }

    /**
     * @notice increase the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function incrementQueuedValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
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
    function reduceQueuedValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
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
    function incrementActiveValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
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
    function reduceActiveValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_NETWORK_POOL) {
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
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _operatorId operator ID
     */
    function incrementWithdrawValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_SLASHING_MANAGER) {
        if (_operatorId == 0) revert OperatorNotRegistered();
        address nodeOperator = operatorByOperatorId[_operatorId];
        operatorRegistry[nodeOperator].withdrawnValidatorCount++;
        emit IncrementedWithdrawnValidatorsCount(
            operatorRegistry[nodeOperator].operatorId,
            operatorRegistry[nodeOperator].withdrawnValidatorCount
        );
    }

    function getOperatorCount() external view override returns (uint256 _operatorCount) {
        _operatorCount = nextOperatorId - 1;
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
        // while (_operatorStartIndex < operatorCount) {
        //     if (
        //         operatorRegistry[_operatorStartIndex].staderPoolType == _poolType &&
        //         operatorRegistry[_operatorStartIndex].validatorCount >
        //         operatorRegistry[_operatorStartIndex].activeValidatorCount
        //     ) {
        //         outputOperatorIds[counter] = (operatorRegistry[_operatorStartIndex].operatorId);
        //         counter++;
        //     }
        //     _operatorStartIndex++;
        //     if (_operatorStartIndex == operatorCount) {
        //         _operatorStartIndex = 0;
        // }
        if (counter == _requiredOperatorCount) {
            return (outputOperatorIds, _operatorStartIndex);
        }
        // }
    }
}
