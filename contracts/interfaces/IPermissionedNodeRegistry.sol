pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import './INodeRegistry.sol';

interface IPermissionedNodeRegistry {
    // Error events
    error EmptyNameString();
    error InvalidCountOfKeys();
    error maxKeyLimitReached();
    error OperatorNotOnBoarded();
    error NameCrossedMaxLength();
    error pubkeyAlreadyExist();
    error OperatorIsDeactivate();
    error InvalidLengthOfpubkey();
    error InvalidLengthOfSignature();
    error InvalidSizeOfInputKeys();
    error OperatorAlreadyOnBoarded();
    error NotAPermissionedNodeOperator();

    //Events
    event OnboardedOperator(address indexed _nodeOperator, uint256 _operatorId);
    event AddedKeys(address indexed _nodeOperator, bytes _pubkey, uint256 _validatorId);
    event UpdatedPoolHelper(address _poolSelector);
    event UpdatedSDCollateralAddress(address _sdCollateral);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedELRewardSocializePool(address _elRewardSocializePool);
    event UpdatedMaxKeyPerOperator(uint256 _keyDepositLimit);
    event UpdatedBatchKeyDepositLimit(uint256 _batchKeyDepositLimit);
    event UpdatedValidatorStatus(bytes indexed _pubkey, ValidatorStatus _status);
    event UpdatedQueuedValidatorIndex(uint256 indexed _operatorId, uint256 _nextQueuedValidatorIndex);
    event UpdatedOperatorDetails(address indexed _nodeOperator, string _operatorName, address _rewardAddress);

    // Getters

    function poolId() external view returns (uint8);

    function vaultFactoryAddress() external view returns (address);

    function sdCollateral() external view returns (address);

    function elRewardSocializePool() external view returns (address);

    function nextOperatorId() external view returns (uint256);

    function nextValidatorId() external view returns (uint256);

    function maxKeyPerOperator() external view returns (uint256);

    function BATCH_KEY_DEPOSIT_LIMIT() external view returns (uint256);

    function operatorIdForExcessDeposit() external view returns (uint256);

    function OPERATOR_MAX_NAME_LENGTH() external view returns (uint256);

    function totalActiveValidatorCount() external view returns (uint256);

    function PERMISSIONED_NODE_REGISTRY_OWNER() external view returns (bytes32);

    function VALIDATOR_STATUS_ROLE() external view returns (bytes32);

    function STADER_MANAGER_BOT() external view returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function OPERATOR_STATUS_ROLE() external view returns (bytes32);

    function PERMISSIONED_POOL() external view returns (bytes32);

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
            uint256 initialBondEth
        );

    function validatorIdByPubkey(bytes calldata _pubkey) external view returns (uint256);

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

    function nextQueuedValidatorIndexByOperatorId(uint256) external view returns (uint256);

    function operatorIDByAddress(address) external view returns (uint256);

    function permissionList(address) external view returns (bool);

    function validatorIdsByOperatorId(uint256, uint256) external view returns (uint256);

    function getTotalActiveOperatorCount() external view returns (uint256 _activeOperatorCount);

    function getOperatorTotalKeys(uint256 _operatorId) external view returns (uint256 _totalKeys);

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

    function reportFrontRunValidator(bytes[] calldata _pubkeys) external;

    function computeOperatorAllocationForDeposit(uint256 numValidators)
        external
        returns (uint256[] memory selectedOperatorCapacity);

    function activateNodeOperator(uint256 _operatorId) external;

    function deactivateNodeOperator(uint256 _operatorId) external;

    function increaseTotalActiveValidatorCount(uint256 _count) external;

    function decreaseTotalActiveValidatorCount(uint256 _count) external;

    function updateQueuedValidatorIndex(uint256 _operatorId, uint256 _nextQueuedValidatorIndex) external;

    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status) external;

    function updateSDCollateralAddress(address _sdCollateral) external;

    function updateVaultFactoryAddress(address _vaultFactory) external;

    function updateELRewardSocializePool(address _elRewardSocializePool) external;

    function updateMaxKeyPerOperator(uint256 _keyDepositLimit) external;

    function updateBatchKeyDepositLimit(uint256 _batchKeyDepositLimit) external;

    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external;

    function pause() external;

    function unpause() external;
}
