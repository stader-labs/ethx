// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../IStaderConfig.sol';

interface ISDCollateral {
    struct PoolThresholdInfo {
        uint256 minThreshold;
        uint256 maxThreshold;
        uint256 withdrawThreshold;
        string units;
    }

    // errors
    error InsufficientSDToWithdraw(uint256 operatorSDCollateral);
    error InvalidPoolId();
    error InvalidPoolLimit();
    error SDTransferFailed();
    error NoStateChange();

    // events
    event SDRepaid(address operator, uint256 repayAmount);
    event UpdatedStaderConfig(address indexed staderConfig);
    event SDDeposited(address indexed operator, uint256 sdAmount);
    event UtilizedSDDeposited(address indexed operator, uint256 sdAmount);
    event SDWithdrawn(address indexed operator, uint256 sdAmount);
    event ReducedUtilizedPosition(address indexed operator, uint256 sdAmount);
    event SDSLashedFromUtilize(address operator, uint256 sdSlashFromUtilized);
    event SDSlashed(address indexed operator, address indexed auction, uint256 sdSlashed);
    event UpdatedPoolThreshold(uint8 poolId, uint256 minThreshold, uint256 withdrawThreshold);
    event UpdatedPoolIdForOperator(uint8 poolId, address operator);

    // methods
    function depositSDAsCollateral(uint256 _sdAmount) external;

    function depositSDAsCollateralFor(address _operator, uint256 _sdAmount) external;

    function depositUtilizedSD(address _operator, uint256 _sdAmount) external;

    function reduceUtilizedSDPosition(address operator, uint256 amount) external;

    function withdraw(uint256 _requestedSD) external;

    function slashValidatorSD(uint256 _validatorId, uint8 _poolId) external;

    function maxApproveSD() external;

    // setters
    function updateStaderConfig(address _staderConfig) external;

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _maxThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) external;

    // getters
    function staderConfig() external view returns (IStaderConfig);

    function operatorSDBalance(address) external view returns (uint256);

    function operatorUtilizedSDBalance(address) external view returns (uint256);

    function getOperatorWithdrawThreshold(address _operator) external view returns (uint256 operatorWithdrawThreshold);

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool);

    function getMinimumSDToBond(uint8 _poolId, uint256 _numValidator) external view returns (uint256 _minSDToBond);

    function getRemainingSDToBond(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) external view returns (uint256);

    function getRewardEligibleSD(address _operator) external view returns (uint256 _rewardEligibleSD);

    function convertSDToETH(uint256 _sdAmount) external view returns (uint256);

    function convertETHToSD(uint256 _ethAmount) external view returns (uint256);

    function getOperatorInfo(address _operator)
        external
        view
        returns (
            uint8 _poolId,
            uint256 _operatorId,
            uint256 _validatorCount
        );
}
