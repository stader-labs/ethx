pragma solidity ^0.8.16;

import './interfaces/IStaderPoolHelper.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderPoolHelper is IStaderPoolHelper, Initializable, AccessControlUpgradeable {
    uint8 public override poolTypeCount;
    bytes32 public constant override POOL_SELECTOR_ADMIN = keccak256('POOL_SELECTOR_ADMIN');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    struct Pool {
        string poolName; // pool name
        address poolAddress; //pool contract address
        uint256 queuedValidatorKeys; //total validator registered in the pool
        uint256 activeValidatorKeys; //validator registered on beacon chain for the pool
        uint256 withdrawnValidatorKeys; // count of validator withdrawn for the pool
    }

    mapping(uint8 => Pool) public override staderPool;

    /**
     * @notice initialize with permissioned and permissionLess Pool
     * @dev permissionLess pool at index 0
     * @param _poolSelectorAdmin admin address for pool selector
     * @param _permissionedPoolAddress permissioned pool contract address
     * @param _permissionLessPoolAddress permissionLess pool contract address
     */
    function initialize(
        address _poolSelectorAdmin,
        address _permissionedPoolAddress,
        address _permissionLessPoolAddress
    )
        external
        checkZeroAddress(_poolSelectorAdmin)
        checkZeroAddress(_permissionedPoolAddress)
        checkZeroAddress(_permissionLessPoolAddress)
        initializer
    {
        __AccessControl_init_unchained();
        staderPool[0] = Pool('PERMISSIONLESS', _permissionLessPoolAddress, 0, 0, 0);
        staderPool[1] = Pool('PERMISSIONED', _permissionedPoolAddress, 0, 0, 0);
        poolTypeCount = 2;
        _grantRole(POOL_SELECTOR_ADMIN, _poolSelectorAdmin);
    }

    /**
     * @notice add a new pool in pool selector logic
     * @dev pass all previous pool new updated weights, only callable by admin
     * @param _newPoolName name of new pool
     * @param _newPoolAddress new pool contract address
     */
    function addNewPool(string calldata _newPoolName, address _newPoolAddress)
        external
        override
        checkZeroAddress(_newPoolAddress)
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        staderPool[poolTypeCount] = Pool(_newPoolName, _newPoolAddress, 0, 0, 0);
        poolTypeCount++;
    }

    /**
     * @notice updated the withdraw weights of existing pools
     * @dev only admin can call
     * @param _poolId new withdraw weights of pools
     * @param _poolAddress updated address of the pool
     */
    function updatePoolAddress(uint8 _poolId, address _poolAddress)
        external
        override
        checkZeroAddress(_poolAddress)
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        if (_poolId >= poolTypeCount) revert InvalidPoolType();
        staderPool[_poolId].poolAddress = _poolAddress;
    }

    /**
     * @notice increase the queued validator count for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolId type of the pool
     */
    function incrementQueuedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].queuedValidatorKeys++;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].queuedValidatorKeys);
    }

    /**
     * @notice decrease the queued validator count for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolId type of the pool
     */
    function reduceQueuedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        if (staderPool[_poolId].queuedValidatorKeys == 0) revert NOQueuedValidators();
        staderPool[_poolId].queuedValidatorKeys--;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].queuedValidatorKeys);
    }

    /**
     * @notice increase the registered validator count on beacon chain for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolId type of the pool
     */
    function incrementActiveValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].activeValidatorKeys++;
        emit UpdatedUsedValidatorKeys(_poolId, staderPool[_poolId].activeValidatorKeys);
    }

    /**
     * @notice decrease the registered validator count on beacon chain for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolId type of the pool
     */
    function reduceActiveValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        if (staderPool[_poolId].activeValidatorKeys == 0) revert NoActiveValidators();
        staderPool[_poolId].activeValidatorKeys--;
        emit UpdatedUsedValidatorKeys(_poolId, staderPool[_poolId].activeValidatorKeys);
    }

    /**
     * @notice increase the withdrawn validator count for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolId type of the pool
     */
    function incrementWithdrawnValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].withdrawnValidatorKeys++;
        emit UpdatedWithdrawnValidatorKeys(_poolId, staderPool[_poolId].withdrawnValidatorKeys);
    }

    /** @notice Check for zero address
     * @dev Modifier
     * @param _address the address to check
     **/
    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }
}
