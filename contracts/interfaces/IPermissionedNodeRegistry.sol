pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

interface IPermissionedNodeRegistry {
    error NoKeysProvided();
    error EmptyNameString();
    error NOActiveOperator();
    error OperatorNotActive();
    error PubKeyDoesNotExist();
    error maxKeyLimitReached();
    error OperatorAlreadyActive();
    error OperatorNotOnBoarded();
    error NameCrossedMaxLength();
    error InvalidSizeOfInputKeys();
    error OperatorAlreadyOnBoarded();
    error NotAPermissionedNodeOperator();

    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubKey, uint256 _validatorId);
    event ValidatorMarkedReadyToDeposit(bytes _pubKey, uint256 _validatorId);
    event ReducedQueuedValidatorsCount(uint256 _operatorId, uint256 _queuedValidatorCount);
    event IncrementedActiveValidatorsCount(uint256 _operatorId, uint256 _activeValidatorCount);
    event ReducedActiveValidatorsCount(uint256 _operatorId, uint256 _activeValidatorCount);
    event IncrementedWithdrawnValidatorsCount(uint256 _operatorId, uint256 _withdrawnValidators);
    event UpdatedPoolHelper(address _poolSelector);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedKeyDepositLimit(uint256 _keyDepositLimit);
    event UpdatedValidatorStatus(bytes indexed _pubKey, ValidatorStatus _status);
    event UpdatedQueuedValidatorIndex(uint256 indexed _operatorId, uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);

    function poolId() external view returns (uint8);

    function vaultFactoryAddress() external view returns (address);

    function sdCollateral() external view returns (address);

    function elRewardSocializePool() external view returns (address);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function KEY_DEPOSIT_LIMIT() external view returns (uint256);

    function operatorIdForExcessValidators() external view returns (uint256);

    function OPERATOR_MAX_NAME_LENGTH() external view returns (uint256);

    function PERMISSIONED_NODE_REGISTRY_OWNER() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function STADER_MANAGER_BOT() external view returns (bytes32);

    function PERMISSIONED_POOL_CONTRACT() external view returns (bytes32);

    function validatorRegistry(uint256)
        external
        view
        returns (
            ValidatorStatus status,
            bytes calldata pubKey,
            bytes calldata signature,
            address withdrawVaultAddress,
            uint256 operatorId
        );

    function validatorIdByPubKey(bytes calldata _pubKey) external view returns (uint256);

    function operatorStructById(uint256)
        external
        view
        returns (
            bool active,
            string calldata operatorName,
            address payable operatorRewardAddress,
            address operatorAddress,
            uint256 nextQueuedValidatorIndex,
            uint256 initializedValidatorCount,
            uint256 queuedValidatorCount,
            uint256 activeValidatorCount,
            uint256 withdrawnValidatorCount
        );

    function operatorIDByAddress(address) external view returns (uint256);

    function permissionList(address) external view returns (bool);

    function whitelistPermissionedNOs(address[] calldata _permissionedNOs) external;

    function operatorQueuedValidators(uint256, uint256) external view returns (uint256);

    function onboardNodeOperator(string calldata _operatorName, address payable _operatorRewardAddress)
        external
        returns (address mevFeeRecipientAddress);

    function addValidatorKeys(
        bytes[] calldata _validatorPubKey,
        bytes[] calldata _validatorSignature,
        bytes32[] calldata _depositDataRoot
    ) external;

    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys) external;

    function computeOperatorAllocationForDeposit(uint256 numValidators)
        external
        returns (uint256[] memory selectedOperatorCapacity);

    function activateNodeOperator(uint256 _operatorId) external;

    function deactivateNodeOperator(uint256 _operatorId) external;

    function reduceQueuedValidatorsCount(uint256 _operatorId, uint256 _count) external;

    function increaseActiveValidatorsCount(uint256 _operatorId, uint256 _count) external;

    function reduceActiveValidatorsCount(uint256 _operatorId, uint256 _count) external;

    function increaseWithdrawnValidatorsCount(uint256 _operatorId, uint256 _count) external;

    function updateQueuedValidatorIndex(uint256 _operatorId, uint256 _nextQueuedValidatorIndex) external;

    function updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status) external;

    function updateVaultFactoryAddress(address _vaultFactory) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function getTotalActiveOperatorCount() external view returns (uint256 _operatorCount);

    function getOperatorTotalKeys(uint256 _operatorId) external view returns (uint256 _totalKeys);

    function pause() external;

    function unpause() external;
}
