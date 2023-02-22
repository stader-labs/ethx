// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISDCollateral {
    function depositSDAsCollateral(uint256 _sdAmount) external;

    function withdraw(uint256 _requestedSD) external;

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _lower,
        uint256 _withdrawThreshold,
        uint256 _upper,
        string memory _units
    ) external;

    function updatePoolIdForOperator(uint8 _poolId, address _operator) external;

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool);

    function getOperatorSDBalance(address _operator) external view returns (uint256);
}
