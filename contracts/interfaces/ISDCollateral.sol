// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISDCollateral {
    // function depositXSDAsCollateral(uint256 _xsdAmount) external;

    // function depositSDAsCollateral(uint256 _sdAmount) external;

    // function updatePoolThreshold(uint8 _poolId, uint256 _lower, uint256 _upper, string memory _units) external;

    function hasEnoughXSDCollateral(
        address _operator,
        uint8 _poolId,
        uint32 _numValidators
    ) external view returns (bool);
}
