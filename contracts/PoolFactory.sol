// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/INodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolFactory is IPoolFactory, Initializable, AccessControlUpgradeable {
    bytes32 public constant POOL_FACTORY_ADMIN = keccak256('POOL_FACTORY_ADMIN');

    mapping(uint8 => Pool) public override pools;
    uint8 public override poolCount;

    function initialize(address _admin) external initializer {
        Address.checkNonZeroAddress(_admin);
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Add a new pool.
     * @dev This function should only be called by the owner of the contract.
     * @param _poolName The name of the new pool.
     * @param _poolAddress The address of the new pool contract.
     */
    function addNewPool(string calldata _poolName, address _poolAddress)
        external
        override
        onlyRole(POOL_FACTORY_ADMIN)
    {
        require(bytes(_poolName).length > 0, 'Pool name cannot be empty');
        Address.checkNonZeroAddress(_poolAddress);

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
    function updatePoolAddress(uint8 _poolId, address _newPoolAddress)
        external
        override
        validPoolId(_poolId)
        onlyRole(POOL_FACTORY_ADMIN)
    {
        Address.checkNonZeroAddress(_newPoolAddress);

        pools[_poolId].poolAddress = _newPoolAddress;

        emit PoolAddressUpdated(_poolId, _newPoolAddress);
    }

    function getTotalActiveValidatorCount() external view override returns (uint256) {
        uint256 totalActiveValidatorCount;
        for (uint8 i = 1; i <= poolCount; i++) {
            totalActiveValidatorCount += this.getActiveValidatorCountByPool(i);
        }
        return totalActiveValidatorCount;
    }

    function getQueuedValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalQueuedValidatorCount();
    }

    function getActiveValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalActiveValidatorCount();
    }

    function getAllActiveValidators() public view override returns (Validator[] memory) {
        Validator[] memory allValidators = new Validator[](this.getTotalActiveValidatorCount());
        uint256 index;
        for (uint8 i = 1; i <= poolCount; i++) {
            Validator[] memory validators = IStaderPoolBase(pools[i].poolAddress).getAllActiveValidators();
            for (uint256 j = 0; j < validators.length; j++) {
                allValidators[index] = validators[j];
                index++;
            }
        }
        return allValidators;
    }

    function retrieveValidator(bytes calldata _pubkey) public view override returns (Validator memory) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (getValidatorByPool(i, _pubkey).pubkey.length == 0) continue;

            return getValidatorByPool(i, _pubkey);
        }
        Validator memory emptyValidator;

        return emptyValidator;
    }

    function getValidatorByPool(uint8 _poolId, bytes calldata _pubkey) public view override returns (Validator memory) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getValidator(_pubkey);
    }

    // Modifiers
    modifier validPoolId(uint8 _poolId) {
        require(_poolId > 0 && _poolId <= this.poolCount(), 'Invalid pool ID');
        _;
    }
}
