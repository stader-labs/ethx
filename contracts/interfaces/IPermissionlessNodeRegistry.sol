// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionlessNodeRegistry {
    // Error events
    error TransferFailed();
    error EmptyNameString();
    error UNEXPECTED_STATUS();
    error NameCrossedMaxLength();
    error OperatorNotOnBoarded();
    error InvalidBondEthValue();
    error InSufficientBalance();
    error OperatorAlreadyOnBoarded();
    error InvalidKeyCount();
    error PubkeyAlreadyExist();
    error PubkeyDoesNotExist();
    error InvalidStartAndEndIndex();
    error OperatorIsDeactivate();
    error InvalidLengthOfPubkey();
    error InvalidLengthOfSignature();
    error MisMatchingInputKeysSize();
    error maxKeyLimitReached();
    error PubkeyNotFoundOrDuplicateInput();
    error CooldownNotComplete();
    error NoChangeInState();

    //Events
    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubkey, uint256 _validatorId);
    event ValidatorWithdrawn(bytes indexed _pubkey, uint256 _validatorId);
    event ValidatorMarkedReadyToDeposit(bytes indexed _pubkey, uint256 _validatorId);
    event ValidatorMarkedAsFrontRunned(bytes indexed _frontRunnedPubkey, uint256 _validatorId);
    event ValidatorStatusMarkedAsInvalidSignature(bytes indexed invalidSignaturePubkey, uint256 _validatorId);

    event UpdatedInputKeyCountLimit(uint16 _inputKeyCountLimit);
    event UpdatedMaxKeyPerOperator(uint64 _keyDepositLimit);
    event ValidatorDepositTimeSet(uint256 _validatorId, uint256 _depositTime);
    event UpdatedNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);
    event UpdatedSocializingPoolState(uint256 _operatorId, bool _optedForSocializingPool, uint256 timestamp);

    //Getters

    function PERMISSIONLESS_NODE_REGISTRY_OWNER() external returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function VALIDATOR_STATUS_ROLE() external returns (bytes32);

    function PERMISSIONLESS_POOL() external returns (bytes32);

    function poolId() external view returns (uint8);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function validatorQueueSize() external view returns (uint256);

    function nextQueuedValidatorIndex() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function inputKeyCountLimit() external view returns (uint16);

    function maxKeyPerOperator() external view returns (uint64);

    function PRE_DEPOSIT() external view returns (uint256);

    function FRONT_RUN_PENALTY() external view returns (uint256);

    function collateralETH() external view returns (uint256);

    function socializePoolRewardDistributionCycle() external view returns (uint256);

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
            address operatorAddress
        );

    function operatorIDByAddress(address) external view returns (uint256);

    function validatorIdsByOperatorId(uint256, uint256) external view returns (uint256);

    function getOperatorTotalKeys(uint256 _operatorId) external view returns (uint256 _totalKeys);

    function getOperatorRewardAddress(uint256 _operatorId) external view returns (address payable);

    //Setters

    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external returns (address mevFeeRecipientAddress);

    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external payable;

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunnedPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external;

    function updateNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex) external;

    function updateDepositStatusAndTime(uint256 _validatorId) external;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function transferCollateralToPool(uint256 _amount) external;

    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status) external;

    function updateInputKeyCountLimit(uint16 _batchKeyDepositLimit) external;

    function updateMaxKeyPerOperator(uint64 _keyDepositLimit) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function changeSocializingPoolState(bool _optInForSocializingPool)
        external
        returns (address mevFeeRecipientAddress);

    function pause() external;

    function unpause() external;
}
