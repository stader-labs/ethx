// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../IStaderConfig.sol';

interface ISDCollateral {
    // errors
    error InsufficientSDCollateral(uint256 operatorSDCollateral);
    error InsufficientWithdrawableSD(uint256 withdrawableSD);
    error InvalidPoolId();
    error InvalidPoolLimit();
    error SDTransferFailed();

    struct PoolThresholdInfo {
        uint256 minThreshold;
        uint256 withdrawThreshold;
        string units;
    }

    // methods
    function depositSDAsCollateral(uint256 _sdAmount) external;

    function withdraw(uint256 _requestedSD) external;

    function slashSD(address _operator, uint256 _sdToSlash) external returns (uint256 _sdSlashed);

    function maxApproveSD(address spenderAddr) external;

    // setters
    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) external;

    function updatePoolIdForOperator(uint8 _poolId, address _operator) external;

    // getters
    function staderConfig() external view returns (IStaderConfig);

    function totalSDCollateral() external view returns (uint256);

    function poolIdByOperator(address) external view returns (uint8);

    function operatorSDBalance(address) external view returns (uint256);

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool);

    function getOperatorPoolId(address _operator) external view returns (uint8 _poolId);

    function getMinimumSDToBond(uint8 _poolId, uint256 _numValidator) external view returns (uint256 _minSDToBond);

    function getRemainingSDToBond(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) external view returns (uint256);

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) external view returns (uint256);

    function convertSDToETH(uint256 _sdAmount) external view returns (uint256);

    function convertETHToSD(uint256 _ethAmount) external view returns (uint256);
}
