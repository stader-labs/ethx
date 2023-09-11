// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './ISSVNetworkCore.sol';

interface ISSVNetworkViews {
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
    event Initialized(uint8 version);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed implementation);

    function acceptOwnership() external;

    function getBalance(
        address owner,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external view returns (uint256);

    function getBurnRate(
        address owner,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external view returns (uint256);

    function getLiquidationThresholdPeriod() external view returns (uint64);

    function getMinimumLiquidationCollateral() external view returns (uint256);

    function getNetworkEarnings() external view returns (uint256);

    function getNetworkFee() external view returns (uint256);

    function getOperatorById(uint64 operatorId)
        external
        view
        returns (
            address,
            uint256,
            uint32,
            address,
            bool,
            bool
        );

    function getOperatorDeclaredFee(uint64 operatorId)
        external
        view
        returns (
            uint256,
            uint64,
            uint64
        );

    function getOperatorEarnings(uint64 id) external view returns (uint256);

    function getOperatorFee(uint64 operatorId) external view returns (uint256);

    function getOperatorFeeIncreaseLimit() external view returns (uint64 operatorMaxFeeIncrease);

    function getOperatorFeePeriods()
        external
        view
        returns (uint64 declareOperatorFeePeriod, uint64 executeOperatorFeePeriod);

    function getValidator(address owner, bytes memory publicKey) external view returns (bool active);

    function getValidatorsPerOperatorLimit() external view returns (uint32);

    function getVersion() external view returns (string memory version);

    function initialize(address ssvNetwork_) external;

    function isLiquidatable(
        address owner,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external view returns (bool);

    function isLiquidated(
        address owner,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external view returns (bool);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function proxiableUUID() external view returns (bytes32);

    function renounceOwnership() external;

    function ssvNetwork() external view returns (address);

    function transferOwnership(address newOwner) external;

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
