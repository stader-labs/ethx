// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPoolSelector {
    // Error
    error InvalidTargetWeight();
    error InvalidNewTargetInput();
    error InvalidSumOfPoolWeights();
    error NotEnoughInitializedValidators();
    error InputBatchLimitIsIdenticalToCurrent();

    //Events

    event UpdatedPoolWeight(uint8 indexed poolId, uint256 poolWeight);
    event UpdatePoolAllocationMaxSize(uint16 _poolAllocationMaxSize);
    event UpdatedStaderConfig(address _staderConfig);

    // Getters
    function poolIdForExcessDeposit() external view returns (uint8); // returns the ID of the pool with excess supply

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_STAKE_POOL_MANAGER() external view returns (bytes32);

    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        returns (uint256[] memory poolWiseValidatorsToDeposit);
}
