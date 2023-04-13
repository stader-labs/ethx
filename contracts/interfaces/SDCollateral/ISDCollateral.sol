// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../IStaderConfig.sol';

interface ISDCollateral {
    struct PoolThresholdInfo {
        uint256 minThreshold;
        uint256 withdrawThreshold;
        string units;
    }

    struct WithdrawRequestInfo {
        uint256 lastWithdrawReqTimestamp;
        uint256 totalSDWithdrawReqAmount;
    }

    // errors
    error InsufficientSDToWithdraw(uint256 operatorSDCollateral);
    error InvalidPoolId();
    error InvalidPoolLimit();
    error SDTransferFailed();
    error InvalidExecutor();
    error AlreadyClaimed();
    error ClaimNotReady();
    error NoStateChange();

    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event SDDeposited(address indexed operator, uint256 sdAmount);
    event SDWithdrawRequested(address indexed operator, uint256 requestedSD);
    event SDClaimed(address indexed operator, uint256 requestedSD);
    event SDSlashed(address indexed operator, address indexed auction, uint256 sdToSlash);
    event UpdatedPoolThreshold(uint8 poolId, uint256 minThreshold, uint256 withdrawThreshold);
    event UpdatedPoolIdForOperator(uint8 poolId, address operator);
    event WithdrawDelayUpdated(uint256 withdrawDelay);

    // methods
    function depositSDAsCollateral(uint256 _sdAmount) external;

    function requestWithdraw(uint256 _requestedSD) external;

    function claimWithdraw() external;

    function slashValidatorSD(uint256 _validatorId, uint8 _poolId) external returns (uint256 _sdSlashed);

    function maxApproveSD(address spenderAddr) external;

    // setters
    function updateStaderConfig(address _staderConfig) external;

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) external;

    function setWithdrawDelay(uint256 _withdrawDelay) external;

    // getters
    function staderConfig() external view returns (IStaderConfig);

    function totalSDCollateral() external view returns (uint256);

    function withdrawDelay() external view returns (uint256);

    function operatorSDBalance(address) external view returns (uint256);

    function withdrawReq(address _operator)
        external
        view
        returns (uint256 _lastWithdrawReqTimestamp, uint256 _totalSDWithdrawReqAmount);

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

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) external view returns (uint256);

    function convertSDToETH(uint256 _sdAmount) external view returns (uint256);

    function convertETHToSD(uint256 _ethAmount) external view returns (uint256);
}
