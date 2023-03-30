// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISDCollateral {
    // errors
    error InsufficientSDToWithdraw();

    function depositSDAsCollateral(uint256 _sdAmount) external;

    function withdraw(uint256 _requestedSD) external;

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) external;

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool);
}
