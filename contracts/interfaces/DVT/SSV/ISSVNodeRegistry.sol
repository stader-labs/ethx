// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../INodeRegistry.sol';

import '../../../library/ValidatorStatus.sol';

struct SSVOperator {
    bool operatorType; // 0 for permissionless and 1 for permissioned
    string operatorName; // name of the operator
    address payable operatorRewardAddress; //Eth1 address of node for reward
    address operatorAddress; // address of operator to interact with stader
    uint64 operatorSSVID; // operator ID on SSV Network
    uint64 keyShareCount; // count of key-share operator is running
    uint256 bondAmount; // amount of ETH bond for new key shares
}

interface ISSVNodeRegistry {
    error InvalidKeyCount();
    error PageNumberIsZero();
    error UNEXPECTED_STATUS();
    error InvalidBondAmount();
    error DifferentClusterSize();
    error ValidatorNotWithdrawn();
    error InvalidCollateralAmount();
    error MisMatchingInputKeysSize();
    error TooManyVerifiedKeysReported();
    error InputSizeIsMoreThanBatchSize();
    error TooManyWithdrawnKeysReported();
    error CallerFailingSSVOperatorChecks();
    error DuplicatePoolIDOrPoolNotAdded();
    error OperatorNotOnboardOrPermissioned();
    error OperatorAlreadyOnBoardedInProtocol();
    error NotSufficientCollateralPerKeyShare();
    error NotSufficientCollateralPerValidator();

    event OperatorWhitelisted(address operator);
    event UpdatedStaderConfig(address staderConfig);
    event MarkedValidatorStatusAsPreDeposit(bytes pubkey);
    event UpdatedInputKeyCountLimit(uint256 inputKeyCountLimit);
    event ValidatorWithdrawn(bytes pubkey, uint256 validatorId);
    event SSVOperatorOnboard(address operator, uint256 operatorId);
    event UpdatedVerifiedKeyBatchSize(uint256 verifiedKeysBatchSize);
    event BondDeposited(address operator, uint256 depositBondAmount);
    event ValidatorMarkedAsFrontRunned(bytes pubkey, uint256 validatorId);
    event UpdatedNextQueuedValidatorIndex(uint256 nextQueuedValidatorIndex);
    event IncreasedTotalActiveValidatorCount(uint256 totalActiveValidatorCount);
    event DecreasedTotalActiveValidatorCount(uint256 totalActiveValidatorCount);
    event ValidatorStatusMarkedAsInvalidSignature(bytes pubkey, uint256 validatorId);
    event AddedValidatorKey(address indexed nodeOperator, bytes pubkey, uint256 validatorId);
    event UpdatedBatchSizeToRemoveValidatorFromSSV(uint64 batchSizeToRemoveValidatorFromSSV);
    event UpdatedBatchSizeToRegisterValidatorWithSSV(uint64 batchSizeToRegisterValidatorFromSSV);

    // function withdrawnValidators(bytes[] calldata _pubkeys) external;

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external;

    // return validator struct for a validator Id
    function validatorRegistry(uint256)
        external
        view
        returns (
            ValidatorStatus status,
            bytes calldata pubkey,
            bytes calldata preDepositSignature,
            bytes calldata depositSignature,
            address withdrawVaultAddress,
            uint256 operatorId,
            uint256 depositTime,
            uint256 withdrawnTime
        );

    // returns the operator struct given operator Id
    function operatorStructById(uint64)
        external
        view
        returns (
            bool operatorType,
            string calldata operatorName,
            address payable operatorRewardAddress,
            address operatorAddress,
            uint64 operatorSSVID,
            uint64 keyShareCount,
            uint256 bondAmount
        );

    function onlyPreDepositValidator(bytes calldata _pubkey) external view;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function nextQueuedValidatorIndex() external view returns (uint256);

    function updateNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex) external;

    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit) external;

    function updateBatchSizeToRemoveValidatorFromSSV(uint64 _batchSizeToRemoveValidatorFromSSV) external;

    function updateBatchSizeToRegisterValidatorFromSSV(uint64 _batchSizeToRegisterValidatorFromSSV) external;

    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external;

    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize) external view returns (Validator[] memory);

    // returns the total number of queued validators across all operators
    function getTotalQueuedValidatorCount() external view returns (uint256);

    // returns the total number of active validators across all operators
    function getTotalActiveValidatorCount() external view returns (uint256);

    function getCollateralETH() external view returns (uint256);

    function getOperatorTotalKeys(uint256 _operatorId) external view returns (uint256 _totalKeys);

    function operatorIDByAddress(address) external view returns (uint64);

    // function getOperatorRewardAddress(uint256 _operatorId) external view returns (address payable);

    function isExistingPubkey(bytes calldata _pubkey) external view returns (bool);

    function isExistingOperator(address _operAddr) external view returns (bool);

    function POOL_ID() external view returns (uint8);

    function CLUSTER_SIZE() external view returns (uint8);

    function inputKeyCountLimit() external view returns (uint16);

    function nextOperatorId() external view returns (uint64);

    function nextValidatorId() external view returns (uint256);

    function verifiedKeyBatchSize() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

    function getOperatorsIdsForValidatorId(uint256 validatorId) external view returns (uint64[] memory);
}
