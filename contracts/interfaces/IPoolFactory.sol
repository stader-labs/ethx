// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

// Interface for the PoolFactory contract
interface IPoolFactory {
    // Events
    event PoolAdded(string poolName, address poolAddress);
    event PoolAddressUpdated(uint8 indexed poolId, address poolAddress);

    // Struct representing a pool
    struct Pool {
        string poolName;
        address poolAddress;
    }

    // returns the details of a specific pool
    function pools(uint8) external view returns (string calldata poolName, address poolAddress);

    // Pool functions
    function addNewPool(string calldata _poolName, address _poolAddress) external;

    function updatePoolAddress(uint8 _poolId, address _poolAddress) external;

    // Pool getters
    function poolCount() external view returns (uint8); // returns the number of pools in the factory

    function getActiveValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of active validators in a specific pool

    function getQueuedValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of queued validators in a specific pool
}
