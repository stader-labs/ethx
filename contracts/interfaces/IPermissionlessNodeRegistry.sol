// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionlessNodeRegistry {
    // Errors
    error TransferFailed();
    error InvalidBondEthValue();
    error InSufficientBalance();
    error PubkeyNotFoundOrDuplicateInput();
    error CooldownNotComplete();
    error NoChangeInState();

    // Events
    event ValidatorMarkedReadyToDeposit(bytes indexed pubkey, uint256 validatorId);
    event UpdatedNextQueuedValidatorIndex(uint256 nextQueuedValidatorIndex);
    event UpdatedSocializingPoolState(uint256 operatorId, bool optedForSocializingPool, uint256 block);
    event TransferredCollateralToPool(uint256 amount);

    //Getters

    function PERMISSIONLESS_NODE_REGISTRY_OWNER() external returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function PERMISSIONLESS_POOL() external returns (bytes32);

    function poolId() external view returns (uint8);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function validatorQueueSize() external view returns (uint256);

    function nextQueuedValidatorIndex() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function inputKeyCountLimit() external view returns (uint16);

    function maxNonTerminalKeyPerOperator() external view returns (uint64);

    function PRE_DEPOSIT() external view returns (uint256);

    function FRONT_RUN_PENALTY() external view returns (uint256);

    function collateralETH() external view returns (uint256);

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

    function queuedValidators(uint256) external view returns (uint256);

    function validatorIdsByOperatorId(uint256, uint256) external view returns (uint256);

    function nodeELRewardVaultByOperatorId(uint256) external view returns (address);

    function getAllSocializingPoolOptOutOperators(uint256 _pageNumber, uint256 _pageSize)
        external
        view
        returns (address[] memory);

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

    function updateDepositStatusAndBlock(uint256 _validatorId) external;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function transferCollateralToPool(uint256 _amount) external;

    function updateInputKeyCountLimit(uint16 _batchKeyDepositLimit) external;

    function updateMaxNonTerminalKeyPerOperator(uint64 _maxNonTerminalKeyPerOperator) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function changeSocializingPoolState(bool _optInForSocializingPool)
        external
        returns (address mevFeeRecipientAddress);

    function pause() external;

    function unpause() external;
}
