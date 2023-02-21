pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionlessNodeRegistry {
    // Error events
    error InvalidIndex();
    error TransferFailed();
    error EmptyNameString();
    error NameCrossedMaxLength();
    error pubkeyDoesNotExist();
    error OperatorNotOnBoarded();
    error InvalidBondEthValue();
    error InSufficientBalance();
    error OperatorAlreadyOnBoarded();
    error NoQueuedValidatorLeft();
    error NoActiveValidatorLeft();
    error NoKeysProvided();
    error pubkeyAlreadyExist();
    error InvalidLengthOfpubkey();
    error InvalidLengthOfSignature();
    error InvalidSizeOfInputKeys();
    error ValidatorInPreDepositState();

    //Events
    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubkey, uint256 _validatorId);
    event ValidatorMarkedReadyToDeposit(bytes _pubkey, uint256 _validatorId);
    event UpdatedQueuedAndActiveValidatorsCount(
        uint256 _operatorId,
        uint256 _queuedValidatorCount,
        uint256 _activeValidatorCount
    );
    event UpdatedActiveAndWithdrawnValidatorsCount(
        uint256 _operatorId,
        uint256 _activeValidatorCount,
        uint256 _withdrawnValidators
    );
    event UpdatedPoolFactoryAddress(address _poolFactoryAddress);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedPermissionlessPoolAddress(address _permissionlessPool);
    event UpdatedNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);
    event UpdatedSocializingPoolState(uint256 _operatorId, bool _optedForSocializingPool, uint256 timestamp);

    //Getters

    function PERMISSIONLESS_NODE_REGISTRY_OWNER() external returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function VALIDATOR_STATUS_ROLE() external returns (bytes32);

    function PERMISSIONLESS_POOL() external returns (bytes32);

    function STADER_MANAGER_BOT() external returns (bytes32);

    function poolId() external view returns (uint8);

    function poolFactoryAddress() external view returns (address);

    function vaultFactoryAddress() external view returns (address);

    function sdCollateral() external view returns (address);

    function elRewardSocializePool() external view returns (address);

    function permissionlessPool() external view returns (address);

    function staderInsuranceFund() external view returns (address);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function validatorQueueSize() external view returns (uint256);

    function nextQueuedValidatorIndex() external view returns (uint256);

    function totalInitializedValidatorCount() external view returns (uint256);

    function totalQueuedValidatorCount() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function totalWithdrawnValidatorCount() external view returns (uint256);

    function PRE_DEPOSIT() external view returns (uint256);

    function FRONT_RUN_PENALTY() external view returns (uint256);

    function collateralETH() external view returns (uint256);

    function OPERATOR_MAX_NAME_LENGTH() external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            ValidatorStatus status,
            bool isFrontRun,
            bytes calldata pubkey,
            bytes calldata signature,
            address withdrawVaultAddress,
            uint256 operatorId,
            uint256 initialBondEth
        );

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

    function queuedValidators(uint256) external view returns (uint256);

    function operatorStructById(uint256)
        external
        view
        returns (
            bool active,
            bool optedForSocializingPool,
            string calldata operatorName,
            address payable operatorRewardAddress,
            address operatorAddress,
            uint256 initializedValidatorCount,
            uint256 queuedValidatorCount,
            uint256 activeValidatorCount,
            uint256 withdrawnValidatorCount
        );

    function operatorIDByAddress(address) external view returns (uint256);

    function socializingPoolStateChangeTimestamp(uint256) external view returns (uint256);

    function getOperatorTotalKeys(address _nodeOperator) external view returns (uint256 _totalKeys);

    //Setters

    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external returns (address mevFeeRecipientAddress);

    function addValidatorKeys(bytes[] calldata _validatorpubkey, bytes[] calldata _validatorSignature) external payable;

    function markValidatorReadyToDeposit(bytes[] calldata _pubkeys) external;

    function updateQueuedAndActiveValidatorsCount(uint256 _operatorID) external;

    function updateActiveAndWithdrawnValidatorsCount(uint256 _operatorID) external;

    function updateNextQueuedValidatorIndex(uint256 _count) external;

    function transferCollateralToPool(uint256 _amount) external;

    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status) external;

    function updatePoolFactoryAddress(address _staderPoolSelector) external;

    function updateVaultFactoryAddress(address _vaultFactoryAddress) external;

    function updatePermissionlessPoolAddress(address _permissionlessPool) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function changeSocializingPoolState(bool _optedForSocializingPool) external;

    function pause() external;

    function unpause() external;
}
