// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPoolSelector {
    // Error events
    error InvalidTargetWeight();
    error InvalidNewTargetInput();
    error InvalidSumOfPoolTargets();
    error NotEnoughInitializedValidators();
    error InputBatchLimitIsIdenticalToCurrent();

    // Getters
    function poolIdForExcessDeposit() external view returns (uint8); // returns the ID of the pool with excess supply

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_STAKE_POOL_MANAGER() external view returns (bytes32);

    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        returns (uint256[] memory poolWiseValidatorsToDeposit);
}
