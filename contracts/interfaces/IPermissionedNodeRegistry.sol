// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionedNodeRegistry {
    // Error events
    error EmptyNameString();
    error InvalidKeyCount();
    error maxKeyLimitReached();
    error OperatorNotOnBoarded();
    error NameCrossedMaxLength();
    error PubkeyAlreadyExist();
    error PubkeyDoesNotExist();
    error UNEXPECTED_STATUS();
    error OperatorIsDeactivate();
    error InvalidLengthOfPubkey();
    error InvalidStartAndEndIndex();
    error InvalidLengthOfSignature();
    error MisMatchingInputKeysSize();
    error OperatorAlreadyOnBoarded();
    error NotAPermissionedNodeOperator();
    error TooManyVerifiedKeysToDeposit();

    //Events
    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubkey, uint256 _validatorId);
    event ValidatorMarkedAsFrontRunned(bytes indexed _pubkey, uint256 _validatorId);
    event ValidatorWithdrawn(bytes indexed _pubkey, uint256 _validatorId);
    event ValidatorStatusMarkedAsInvalidSignature(bytes indexed _pubkey, uint256 _validatorId);
    event ValidatorDepositTimeSet(uint256 _validatorId, uint256 _depositTime);
    event UpdatedMaxKeyPerOperator(uint64 _keyDepositLimit);
    event UpdatedInputKeyCountLimit(uint256 _batchKeyDepositLimit);
    event UpdatedValidatorStatus(bytes indexed _pubkey, ValidatorStatus _status);
    event UpdatedQueuedValidatorIndex(uint256 indexed _operatorId, uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);

    // Getters

    function poolId() external view returns (uint8);

    function nextOperatorId() external view returns (uint16);

    function nextValidatorId() external view returns (uint256);

    function maxKeyPerOperator() external view returns (uint64);

    function inputKeyCountLimit() external view returns (uint16);

    function operatorIdForExcessDeposit() external view returns (uint16);

    function totalActiveValidatorCount() external view returns (uint256);

    function totalActiveOperatorCount() external view returns (uint16);

    function PERMISSIONED_NODE_REGISTRY_OWNER() external view returns (bytes32);

    function STADER_MANAGER_BOT() external view returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function PERMISSIONED_POOL() external view returns (bytes32);

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

    function operatorStructById(uint16)
        external
        view
        returns (
            bool active,
            bool optedForSocializingPool,
            string calldata operatorName,
            address payable operatorRewardAddress,
            address operatorAddress
        );

    function nextQueuedValidatorIndexByOperatorId(uint16) external view returns (uint256);

    function operatorIDByAddress(address) external view returns (uint16);

    function permissionList(address) external view returns (bool);

    function validatorIdsByOperatorId(uint16, uint256) external view returns (uint256);

    function getOperatorTotalKeys(uint16 _operatorId) external view returns (uint256 _totalKeys);

    function getOperatorRewardAddress(uint16 _operatorId) external view returns (address payable);

    function onlyPreDepositValidator(bytes calldata _pubkey) external view;

    // Setters

    function whitelistPermissionedNOs(address[] calldata _permissionedNOs) external;

    function onboardNodeOperator(string calldata _operatorName, address payable _operatorRewardAddress)
        external
        returns (address mevFeeRecipientAddress);

    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external;

    function computeOperatorAllocationForDeposit(uint256 numValidators)
        external
        returns (uint256[] memory selectedOperatorCapacity);

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkeys,
        bytes[] calldata _frontRunPubkeys,
        bytes[] calldata _invalidSignaturePubkeys
    ) external;

    function activateNodeOperator(uint16 _operatorId) external;

    function deactivateNodeOperator(uint16 _operatorId) external;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function updateQueuedValidatorIndex(uint16 _operatorId, uint256 _nextQueuedValidatorIndex) external;

    function updateDepositStatusAndTime(uint256 _validatorId) external;

    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external;

    function updateMaxKeyPerOperator(uint64 _maxKeyPerOperator) external;

    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function pause() external;

    function unpause() external;
}
