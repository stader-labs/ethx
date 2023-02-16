// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

interface IPoolSelector {
    // Error events
    error InvalidTargetWeight();
    error InvalidNewTargetInput();
    error InvalidSumOfPoolTargets();
    error NotEnoughInitializedValidators();
    error InputBatchLimitIsIdenticalToCurrent();

    // Getters
    function poolIdForExcessSupply() external view returns (uint8); // returns the ID of the pool with excess supply

    function TOTAL_TARGET() external pure returns (uint8); // returns the total target for pools

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function computePoolWiseValidatorsToDeposit(uint256 _pooledEth)
        external
        returns (uint256[] memory poolWiseValidatorsToDeposit);
}
