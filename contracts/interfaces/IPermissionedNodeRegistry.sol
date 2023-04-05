// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionedNodeRegistry {
    // Errors
    error NotAPermissionedNodeOperator();
    error TooManyVerifiedKeysToDeposit();

    // Events
    event OperatorWhitelisted(address permissionedNO);
    event OperatorDeactivated(uint256 operatorID);
    event OperatorActivated(uint256 operatorID);
    event MarkedValidatorStatusAsPreDeposit(bytes indexed pubkey);
    event UpdatedVerifiedKeyBatchSize(uint256 verifiedKeysBatchSize);
    event UpdatedQueuedValidatorIndex(uint256 indexed operatorId, uint256 nextQueuedValidatorIndex);

    // Getters

    function poolId() external view returns (uint8);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function maxNonTerminalKeyPerOperator() external view returns (uint64);

    function inputKeyCountLimit() external view returns (uint16);

    function operatorIdForExcessDeposit() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function totalActiveOperatorCount() external view returns (uint256);

    function STADER_DAO() external view returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function PERMISSIONED_POOL() external view returns (bytes32);

    function PERMISSIONED_NODE_REGISTRY_OWNER() external view returns (bytes32);

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

    function nextQueuedValidatorIndexByOperatorId(uint256) external view returns (uint256);

    function operatorIDByAddress(address) external view returns (uint256);

    function permissionList(address) external view returns (bool);

    function validatorIdsByOperatorId(uint256, uint256) external view returns (uint256);

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

    function computeOperatorAllocationForDeposit(uint256 _numValidators)
        external
        returns (uint256[] memory selectedOperatorCapacity);

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkeys,
        bytes[] calldata _frontRunPubkeys,
        bytes[] calldata _invalidSignaturePubkeys
    ) external;

    function activateNodeOperator(uint256 _operatorId) external;

    function deactivateNodeOperator(uint256 _operatorId) external;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function updateQueuedValidatorIndex(uint256 _operatorId, uint256 _nextQueuedValidatorIndex) external;

    function updateDepositStatusAndBlock(uint256 _validatorId) external;

    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external;

    function updateMaxNonTerminalKeyPerOperator(uint64 _maxNonTerminalKeyPerOperator) external;

    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function pause() external;

    function unpause() external;
}
