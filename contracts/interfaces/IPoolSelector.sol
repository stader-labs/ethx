// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPoolSelector {
    // Error
    error InvalidTargetWeight();
    error InvalidNewTargetInput();
    error InvalidSumOfPoolWeights();

    // Events

    event UpdatedPoolWeight(uint8 indexed poolId, uint256 poolWeight);
    event UpdatedPoolAllocationMaxSize(uint16 poolAllocationMaxSize);
    event UpdatedStaderConfig(address staderConfig);

    // Getters

    // returns the ID of the pool with excess supply
    function poolIdForExcessDeposit() external view returns (uint8);

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function POOL_MANAGER() external view returns (bytes32);

    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        returns (uint256[] memory poolWiseValidatorsToDeposit);
}
