// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderPoolBase.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolFactory is IPoolFactory, Initializable, AccessControlUpgradeable {
    mapping(uint8 => Pool) public override pools;
    uint8 public override poolCount;

    function initialize() external initializer {
        __AccessControl_init_unchained();
    }

    /**
     * @notice Add a new pool.
     * @dev This function should only be called by the owner of the contract.
     * @param _poolName The name of the new pool.
     * @param _poolAddress The address of the new pool contract.
     */
    function addNewPool(string calldata _poolName, address _poolAddress) external override {
        require(bytes(_poolName).length > 0, 'Pool name cannot be empty');
        require(_poolAddress != address(0), 'Pool address cannot be zero');

        pools[poolCount + 1] = Pool({poolName: _poolName, poolAddress: _poolAddress});
        poolCount++;

        emit PoolAdded(_poolName, _poolAddress);
    }

    /**
     * @notice Update the address of a pool.
     * @dev This function should only be called by the owner of the contract.
     * @param _poolId The ID of the pool to update.
     * @param _newPoolAddress The updated address of the pool.
     */
    function updatePoolAddress(uint8 _poolId, address _newPoolAddress) external override validPoolId(_poolId) {
        require(_newPoolAddress != address(0), 'New pool address cannot be zero');

        pools[_poolId].poolAddress = _newPoolAddress;

        emit PoolAddressUpdated(_poolId, _newPoolAddress);
    }

    function getTotalValidatorCount() external view override returns (uint256) {
        return
            this.getInitializedValidatorCount() +
            this.getQueuedValidatorCount() +
            this.getActiveValidatorCount() +
            this.getWithdrawnValidatorCount();
    }

    function getInitializedValidatorCount() external view override returns (uint256) {
        uint256 total;
        for (uint8 i = 1; i <= poolCount; i++) {
            total += IStaderPoolBase(pools[i].poolAddress).getInitializedValidatorCount();
        }
        return total;
    }

    function getQueuedValidatorCount() external view override returns (uint256) {
        uint256 total;
        for (uint8 i = 1; i <= poolCount; i++) {
            total += IStaderPoolBase(pools[i].poolAddress).getQueuedValidatorCount();
        }
        return total;
    }

    function getActiveValidatorCount() external view override returns (uint256) {
        uint256 total;
        for (uint8 i = 1; i <= poolCount; i++) {
            total += IStaderPoolBase(pools[i].poolAddress).getActiveValidatorCount();
        }
        return total;
    }

    function getWithdrawnValidatorCount() external view override returns (uint256) {
        uint256 total;
        for (uint8 i = 1; i <= poolCount; i++) {
            total += IStaderPoolBase(pools[i].poolAddress).getWithdrawnValidatorCount();
        }
        return total;
    }

    function getInitializedValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getInitializedValidatorCount();
    }

    function getWithdrawnValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getWithdrawnValidatorCount();
    }

    function getQueuedValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getQueuedValidatorCount();
    }

    function getActiveValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getActiveValidatorCount();
    }

    // Modifiers
    modifier validPoolId(uint8 _poolId) {
        require(_poolId > 0 && _poolId <= this.poolCount(), 'Invalid pool ID');
        _;
    }
}
