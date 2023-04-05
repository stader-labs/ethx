// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISDCollateral {
    // errors
    error InsufficientSDToWithdraw();
    error InvalidPoolId();
    error InvalidPoolLimit();

    struct PoolThresholdInfo {
        uint256 minThreshold;
        uint256 withdrawThreshold;
        string units;
    }

    function poolIdByOperator(address) external view returns (uint8);

    function depositSDAsCollateral(uint256 _sdAmount) external;

    function withdraw(uint256 _requestedSD) external;

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) external;

    function updatePoolIdForOperator(uint8 _poolId, address _operator) external;

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool);
}
