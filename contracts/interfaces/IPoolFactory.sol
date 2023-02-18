// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './INodeRegistry.sol';

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

    function getAllValidators() external view returns (Validator[] memory);

    function retrieveValidator(bytes calldata _pubkey) external view returns (Validator memory);

    function getValidatorByPool(uint8 _poolId, bytes calldata _pubkey) external view returns (Validator memory);

    // Pool getters
    function poolCount() external view returns (uint8); // returns the number of pools in the factory

    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all pools

    function getInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all pools

    function getActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all pools

    function getQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all pools

    function getWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all pools

    function getInitializedValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of initialized validators in a specific pool

    function getActiveValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of active validators in a specific pool

    function getQueuedValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of queued validators in a specific pool

    function getWithdrawnValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of withdrawn validators in a specific pool
}
