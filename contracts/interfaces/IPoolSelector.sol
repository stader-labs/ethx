// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPoolSelector {
    // Error
    error InvalidTargetWeight();
    error InvalidNewTargetInput();
    error InvalidSumOfPoolWeights();
    error CallerNotManager();
    error CallerNotOperator();
    error CallerNotPoolManager();

    // Events

    event UpdatedPoolWeight(uint8 indexed poolId, uint256 poolWeight);
    event UpdatedPoolAllocationMaxSize(uint16 poolAllocationMaxSize);
    event UpdatedStaderConfig(address staderConfig);

    // Getters

    // returns the ID of the pool with excess supply
    function poolIdForExcessDeposit() external view returns (uint8);

    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        returns (uint256[] memory poolWiseValidatorsToDeposit);
}
