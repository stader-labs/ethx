// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './ISSVNetworkCore.sol';

interface ISSVNetwork {
    error ApprovalNotWithinTimeframe();
    error CallerNotOwner();
    error CallerNotWhitelisted();
    error ClusterAlreadyEnabled();
    error ClusterDoesNotExists();
    error ClusterIsLiquidated();
    error ClusterNotLiquidatable();
    error ExceedValidatorLimit();
    error FeeExceedsIncreaseLimit();
    error FeeIncreaseNotAllowed();
    error FeeTooLow();
    error IncorrectClusterState();
    error IncorrectValidatorState();
    error InsufficientBalance();
    error InvalidOperatorIdsLength();
    error InvalidPublicKeyLength();
    error MaxValueExceeded();
    error NewBlockPeriodIsBelowMinimum();
    error NoFeeDeclared();
    error NotAuthorized();
    error OperatorAlreadyExists();
    error OperatorDoesNotExist();
    error OperatorsListNotUnique();
    error SameFeeChangeNotAllowed();
    error TargetModuleDoesNotExist();
    error TokenTransferFailed();
    error UnsortedOperatorsList();
    error ValidatorAlreadyExists();
    error ValidatorDoesNotExist();
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event ClusterDeposited(address indexed owner, uint64[] operatorIds, uint256 value, ISSVNetworkCore.Cluster cluster);
    event ClusterLiquidated(address indexed owner, uint64[] operatorIds, ISSVNetworkCore.Cluster cluster);
    event ClusterReactivated(address indexed owner, uint64[] operatorIds, ISSVNetworkCore.Cluster cluster);
    event ClusterWithdrawn(address indexed owner, uint64[] operatorIds, uint256 value, ISSVNetworkCore.Cluster cluster);
    event DeclareOperatorFeePeriodUpdated(uint64 value);
    event ExecuteOperatorFeePeriodUpdated(uint64 value);
    event FeeRecipientAddressUpdated(address indexed owner, address recipientAddress);
    event Initialized(uint8 version);
    event LiquidationThresholdPeriodUpdated(uint64 value);
    event MinimumLiquidationCollateralUpdated(uint256 value);
    event NetworkEarningsWithdrawn(uint256 value, address recipient);
    event NetworkFeeUpdated(uint256 oldFee, uint256 newFee);
    event OperatorAdded(uint64 indexed operatorId, address indexed owner, bytes publicKey, uint256 fee);
    event OperatorFeeCancellationDeclared(address indexed owner, uint64 indexed operatorId);
    event OperatorFeeDeclared(address indexed owner, uint64 indexed operatorId, uint256 blockNumber, uint256 fee);
    event OperatorFeeExecuted(address indexed owner, uint64 indexed operatorId, uint256 blockNumber, uint256 fee);
    event OperatorFeeIncreaseLimitUpdated(uint64 value);
    event OperatorRemoved(uint64 indexed operatorId);
    event OperatorWhitelistUpdated(uint64 indexed operatorId, address whitelisted);
    event OperatorWithdrawn(address indexed owner, uint64 indexed operatorId, uint256 value);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed implementation);
    event ValidatorAdded(
        address indexed owner,
        uint64[] operatorIds,
        bytes publicKey,
        bytes shares,
        ISSVNetworkCore.Cluster cluster
    );
    event ValidatorRemoved(
        address indexed owner,
        uint64[] operatorIds,
        bytes publicKey,
        ISSVNetworkCore.Cluster cluster
    );

    fallback() external;

    function acceptOwnership() external;

    function cancelDeclaredOperatorFee(uint64 operatorId) external;

    function declareOperatorFee(uint64 operatorId, uint256 fee) external;

    function deposit(
        address owner,
        uint64[] memory operatorIds,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function executeOperatorFee(uint64 operatorId) external;

    function getRegisterAuth(address userAddress) external view returns (bool authOperators, bool authValidators);

    function initialize(
        address token_,
        address ssvOperators_,
        address ssvClusters_,
        address ssvDAO_,
        address ssvViews_,
        uint64 minimumBlocksBeforeLiquidation_,
        uint256 minimumLiquidationCollateral_,
        uint32 validatorsPerOperatorLimit_,
        uint64 declareOperatorFeePeriod_,
        uint64 executeOperatorFeePeriod_,
        uint64 operatorMaxFeeIncrease_
    ) external;

    function liquidate(
        address owner,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function proxiableUUID() external view returns (bytes32);

    function reactivate(
        uint64[] memory operatorIds,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function reduceOperatorFee(uint64 operatorId, uint256 fee) external;

    function registerOperator(bytes memory publicKey, uint256 fee) external returns (uint64 id);

    function registerValidator(
        bytes memory publicKey,
        uint64[] memory operatorIds,
        bytes memory sharesData,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function removeOperator(uint64 operatorId) external;

    function removeValidator(
        bytes memory publicKey,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function renounceOwnership() external;

    function setFeeRecipientAddress(address recipientAddress) external;

    function setOperatorWhitelist(uint64 operatorId, address whitelisted) external;

    function setRegisterAuth(
        address userAddress,
        bool authOperator,
        bool authValidator
    ) external;

    function transferOwnership(address newOwner) external;

    function updateDeclareOperatorFeePeriod(uint64 timeInSeconds) external;

    function updateExecuteOperatorFeePeriod(uint64 timeInSeconds) external;

    function updateLiquidationThresholdPeriod(uint64 blocks) external;

    function updateMinimumLiquidationCollateral(uint256 amount) external;

    function updateModule(uint8 moduleId, address moduleAddress) external;

    function updateNetworkFee(uint256 fee) external;

    function updateOperatorFeeIncreaseLimit(uint64 percentage) external;

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;

    function withdraw(
        uint64[] memory operatorIds,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external;

    function withdrawNetworkEarnings(uint256 amount) external;

    function withdrawOperatorEarnings(uint64 operatorId, uint256 amount) external;

    function withdrawOperatorEarnings(uint64 operatorId) external;
}
