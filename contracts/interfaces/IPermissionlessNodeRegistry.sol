pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

interface IPermissionlessNodeRegistry {
    error InvalidIndex();
    error TransferFailed();
    error EmptyNameString();
    error NameCrossedMaxLength();
    error PubKeyDoesNotExist();
    error OperatorNotOnBoarded();
    error InvalidBondEthValue();
    error InSufficientBalance();
    error OperatorAlreadyOnBoarded();
    error NoQueuedValidatorLeft();
    error NoActiveValidatorLeft();
    error NoKeysProvided();
    error InvalidSizeOfInputKeys();
    error ValidatorInPreDepositState();

    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubKey, uint256 _validatorId);
    event ValidatorMarkedReadyToDeposit(bytes _pubKey, uint256 _validatorId);
    event ReducedQueuedValidatorsCount(uint256 _operatorId, uint256 _queuedValidatorCount);
    event IncrementedActiveValidatorsCount(uint256 _operatorId, uint256 _activeValidatorCount);
    event ReducedActiveValidatorsCount(uint256 _operatorId, uint256 _activeValidatorCount);
    event IncrementedWithdrawnValidatorsCount(uint256 _operatorId, uint256 _withdrawnValidators);
    event UpdatedPoolHelper(address _poolSelector);
    event UpdatedVaultFactory(address _vaultFactory);
    event UpdatedNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorName(address indexed _nodeOperator, string _operatorName);
    event UpdatedOperatorRewardAddress(address indexed _nodeOperator, address _rewardAddress);

    function PERMISSIONLESS_NODE_REGISTRY_OWNER() external returns (bytes32);

    function STADER_NETWORK_POOL() external returns (bytes32);

    function poolHelper() external view returns (address);

    function vaultFactory() external view returns (address);

    function elRewardSocializePool() external view returns (address);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function validatorQueueSize() external view returns (uint256);

    function nextQueuedValidatorIndex() external view returns (uint256);

    function collateralETH() external view returns (uint256);

    function OPERATOR_MAX_NAME_LENGTH() external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            ValidatorStatus status,
            bool isWithdrawal,
            bytes calldata pubKey,
            bytes calldata signature,
            bytes calldata withdrawalAddress,
            uint256 operatorId,
            uint256 bondEth,
            uint256 penaltyCount
        );

    function validatorIdByPubKey(bytes calldata _pubKey) external view returns (uint256);

    function queuedValidators(uint256) external view returns (uint256);

    function operatorRegistry(address)
        external
        view
        returns (
            bool optedForSocializingPool,
            string calldata operatorName,
            address payable operatorRewardAddress,
            uint256 operatorId,
            uint256 initializedValidatorCount,
            uint256 queuedValidatorCount,
            uint256 activeValidatorCount,
            uint256 withdrawnValidatorCount
        );

    function operatorAddressByOperatorId(uint256) external view returns (address);

    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external returns (address mevFeeRecipientAddress);

    function addValidatorKeys(
        bytes[] calldata _validatorPubKey,
        bytes[] calldata _validatorSignature,
        bytes32[] calldata _depositDataRoot
    ) external payable;

    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys) external;

    function deleteDepositedQueueValidator(uint256 _keyCount, uint256 _index) external;

    function reduceQueuedValidatorsCount(address _nodeOperator) external;

    function incrementActiveValidatorsCount(address _nodeOperator) external;

    function reduceActiveValidatorsCount(address _nodeOperator) external;

    function incrementWithdrawValidatorsCount(address _nodeOperator) external;

    function updateNextQueuedValidatorIndex(uint256 _count) external;

    function getOperatorCount() external view returns (uint256 _operatorCount);

    function getTotalValidatorKeys(address _nodeOperator) external view returns (uint256 _totalKeys);

    function transferCollateralToPool(uint256 _amount) external;

    function updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status) external;

    function updatePoolSelector(address _staderPoolSelector) external;

    function updateVaultAddress(address _vaultFactory) external;

    function updateOperatorRewardAddress(address payable _rewardAddress) external;

    function updateOperatorName(string calldata _operatorName) external;

    function pause() external;

    function unpause() external;
}