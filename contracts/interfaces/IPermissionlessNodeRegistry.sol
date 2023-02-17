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
    event UpdatedPoolFactoryAddress(address _poolFactoryAddress);
    event UpdatedVaultFactory(address _vaultFactory);
    event UpdatedNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);

    function PERMISSIONLESS_NODE_REGISTRY_OWNER() external returns (bytes32);

    function STADER_NETWORK_POOL() external returns (bytes32);

    function PERMISSIONLESS_POOL() external returns (bytes32);

    function STADER_MANAGER_BOT() external returns (bytes32);

    function poolId() external view returns (uint8);

    function poolFactoryAddress() external view returns (address);

    function vaultFactory() external view returns (address);

    function sdCollateral() external view returns (address);

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
            bytes calldata pubKey,
            bytes calldata signature,
            bytes calldata withdrawalAddress,
            uint256 operatorId,
            uint256 bondEth,
            uint256 penaltyCount
        );

    function validatorIdByPubKey(bytes calldata _pubKey) external view returns (uint256);

    function queuedValidators(uint256) external view returns (uint256);

    function operatorStructById(uint256)
        external
        view
        returns (
            bool optedForSocializingPool,
            string calldata operatorName,
            address payable operatorRewardAddress,
            address operatorAddress,
            uint256 totalKeys,
            uint256 withdrawnKeys
        );

    function operatorIDByAddress(address) external view returns (uint256);

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

    function reduceTotalQueuedValidatorsCount(uint256 _count) external;

    function increaseTotalActiveValidatorsCount(uint256 _count) external;

    function reduceTotalActiveValidatorsCount(uint256 _count) external;

    function increaseTotalWithdrawValidatorsCount(uint256 _operatorId, uint256 _count) external;

    function updateNextQueuedValidatorIndex(uint256 _count) external;

    function getOperatorTotalKeys(uint256 _operatorId) external view returns (uint256 _totalKeys);

    function transferCollateralToPool(uint256 _amount) external;

    function updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status) external;

    function updatePoolFactoryAddress(address _staderPoolSelector) external;

    function updateVaultAddress(address _vaultFactory) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function pause() external;

    function unpause() external;
}
