pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderPoolHelper.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderPoolHelper is IStaderPoolHelper, Initializable, AccessControlUpgradeable {
    using Math for uint256;

    uint8 public override poolCount;
    uint8 public poolIdForExcessSupply;
    uint16 public BATCH_LIMIT;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint8 public constant TOTAL_TARGET = 100;
    bytes32 public constant override POOL_HELPER_ADMIN = keccak256('POOL_HELPER_ADMIN');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    struct Pool {
        uint8 targetShare; // shares of total active validators for the pool
        string poolName; // pool name
        address poolAddress; //pool contract address
        address nodeRegistry; //node registry of the pool
        uint256 initializedValidatorKeys; //validator waiting for pre-signed messages to submit
        uint256 queuedValidatorKeys; //validator in the pool ready to deposit
        uint256 activeValidatorKeys; //validator registered on beacon chain for the pool
        uint256 withdrawnValidatorKeys; // count of validator withdrawn for the pool
    }

    mapping(uint8 => Pool) public override staderPool;

    /**
     * @notice initialize with permissioned and permissionLess Pool
     * @dev pool index start from 1 with permission less pool
     * @param _permissionLessTarget target weight of permissionless pool
     * @param _adminOwner admin address for pool selector
     * @param _permissionLessPoolAddress permissionLess pool contract address
     * @param _permissionLessNodeRegistry permissionLess node registry
     */
    function initialize(
        uint8 _permissionLessTarget,
        address _adminOwner,
        address _permissionLessPoolAddress,
        address _permissionLessNodeRegistry
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_permissionLessPoolAddress);
        Address.checkNonZeroAddress(_permissionLessNodeRegistry);
        if (_permissionLessTarget != TOTAL_TARGET) revert InvalidTargetWeight();
        __AccessControl_init_unchained();
        staderPool[1] = Pool(
            _permissionLessTarget,
            'PERMISSIONLESS',
            _permissionLessPoolAddress,
            _permissionLessNodeRegistry,
            0,
            0,
            0,
            0
        );
        poolCount = 1;
        poolIdForExcessSupply = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice add a new pool in pool selector logic
     * @dev pass all previous pool new updated weights, only callable by admin
     * @param _newTargetShares new targets for all pool including new one
     * @param _newPoolName name of new pool
     * @param _newPoolAddress new pool contract address
     * @param _nodeRegistry node registry of the new pool
     */
    function addNewPool(
        uint8[] calldata _newTargetShares,
        string calldata _newPoolName,
        address _newPoolAddress,
        address _nodeRegistry
    ) external override onlyRole(POOL_HELPER_ADMIN) {
        Address.checkNonZeroAddress(_newPoolAddress);
        Address.checkNonZeroAddress(_nodeRegistry);
        if (poolCount + 1 != _newTargetShares.length) revert InvalidNewPoolInput();
        uint8 totalTarget;
        for (uint8 i = 0; i < _newTargetShares.length; i++) {
            totalTarget += _newTargetShares[i];
            if (totalTarget > TOTAL_TARGET) revert InvalidNewTargetInput();
            staderPool[i + 1].targetShare = _newTargetShares[i];
        }
        if(totalTarget != TOTAL_TARGET) revert InvalidSumOfPoolTargets();

        Pool storage _newPool = staderPool[poolCount + 1];
        _newPool.poolName = _newPoolName;
        _newPool.poolAddress = _newPoolAddress;
        _newPool.nodeRegistry = _nodeRegistry;
        poolCount++;
    }

    /**
     * @notice calculates the amount of validator number to be deposited on beacon chain based on target weight
     * @dev first loop allot validators to match the target share with the constraint of capacity and
     * second loop uses FIFO to keep on exhausting the capacity and updating the starting index of pool for FIFO
     * @param _pooledEth amount of eth ready to deposit on pool manager
     */
    function computePoolWiseValidatorToDeposit(uint256 _pooledEth)
        external
        onlyRole(STADER_NETWORK_POOL)
        returns (uint256[] memory poolWiseValidatorsToDeposit)
    {
        uint256 depositedETh;
        for (uint8 i = 1; i <= poolCount; i++) {
            depositedETh += (staderPool[i].activeValidatorKeys) * DEPOSIT_SIZE;
        }
        uint256 totalEth = depositedETh + _pooledEth;
        uint256 totalValidatorsRequired = totalEth / DEPOSIT_SIZE;
        // new validators to register on beacon chain with `_pooledEth` taking `BATCH_LIMIT` into consideration
        uint256 newValidatorsToDeposit = Math.min(BATCH_LIMIT, _pooledEth / DEPOSIT_SIZE);
        // `validatorsToDeposit` array start with index 1
        uint256[] memory poolCapacity;
        uint256 validatorSpunCount;
        for (uint8 i = 1; i <= poolCount && validatorSpunCount < newValidatorsToDeposit; i++) {
            poolCapacity[i] = staderPool[i].queuedValidatorKeys;
            uint256 currentActiveValidators = staderPool[i].activeValidatorKeys;
            uint256 poolTotalTarget = (staderPool[i].targetShare * totalValidatorsRequired) / 100;
            poolWiseValidatorsToDeposit[i] = Math.min(
                Math.min(poolCapacity[i], poolTotalTarget - currentActiveValidators),
                newValidatorsToDeposit - validatorSpunCount
            );
            poolCapacity[i] -= poolWiseValidatorsToDeposit[i];
            validatorSpunCount += poolWiseValidatorsToDeposit[i];
        }

        // check for more validators to deposit and select pools with excess supply in FIFO
        // and update the starting index of pool for FIFO after every iteration
        if (validatorSpunCount < newValidatorsToDeposit) {
            uint256 remainingValidatorsToDeposit = newValidatorsToDeposit - validatorSpunCount;
            uint8[] memory poolQueue;
            uint8 counter;
            for (uint8 i = poolIdForExcessSupply; i <= poolCount; i++) {
                poolQueue[counter++] = i;
            }
            for (uint8 i = 1; i < poolIdForExcessSupply; i++) {
                poolQueue[counter++] = i;
            }
            for (uint8 i = 0; i <= poolQueue.length; i++) {
                uint256 extraValidatorToDepositInAPool = Math.min(
                    poolCapacity[poolQueue[i]],
                    remainingValidatorsToDeposit
                );
                poolWiseValidatorsToDeposit[poolQueue[i]] += extraValidatorToDepositInAPool;
                remainingValidatorsToDeposit -= extraValidatorToDepositInAPool;
                // Don't have to update poolID if the `remainingValidatorsToDeposit` does not become 0
                // As we have scanned through all pool, will start from same pool in same iteration
                if (remainingValidatorsToDeposit == 0) {
                    poolIdForExcessSupply = poolQueue[(i + 1) % poolQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice update the target weights of existing pools
     * @dev only admin can call
     * @param _poolTarget new target weights of pools
     */
    function updatePoolWeights(uint8[] calldata _poolTarget) external onlyRole(POOL_HELPER_ADMIN){
        if (poolCount != _poolTarget.length) revert InvalidNewPoolInput();
        uint8 totalTarget;
        for (uint8 i = 0; i < _poolTarget.length; i++) {
            totalTarget += _poolTarget[i];
            if (totalTarget > TOTAL_TARGET) revert InvalidNewTargetInput();
            staderPool[i + 1].targetShare = _poolTarget[i];
        }
        if(totalTarget !=TOTAL_TARGET) revert InvalidSumOfPoolTargets();
    }

    /**
     * @notice updated the pool address for pool `_poolId`
     * @dev only admin can call
     * @param _poolId Id of the pool
     * @param _poolAddress updated address of the pool
     */
    function updatePoolAddress(uint8 _poolId, address _poolAddress) external override onlyRole(POOL_HELPER_ADMIN) {
        Address.checkNonZeroAddress(_poolAddress);
        if (_poolId > poolCount) revert InvalidPoolId();
        staderPool[_poolId].poolAddress = _poolAddress;
    }

    /**
     * @notice updated the operator registry address for pool `_poolId`
     * @dev only admin can call
     * @param _poolId Id of the pool
     * @param _nodeRegistry updated node registry address for the pool
     */
    function updatePoolNodeRegistry(uint8 _poolId, address _nodeRegistry)
        external
        override
        onlyRole(POOL_HELPER_ADMIN)
    {
        Address.checkNonZeroAddress(_nodeRegistry);
        if (_poolId > poolCount) revert InvalidPoolId();
        staderPool[_poolId].nodeRegistry = _nodeRegistry;
    }
    
    /**
     * @notice increase the initialized validator count for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function incrementInitializedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].initializedValidatorKeys++;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].initializedValidatorKeys);
    }

    /**
     * @notice reduce the initialized validator count for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function reduceInitializedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        if (staderPool[_poolId].initializedValidatorKeys == 0) revert NoInitializedValidators();
        staderPool[_poolId].initializedValidatorKeys--;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].initializedValidatorKeys);
    }

    /**
     * @notice increase the queued validator count for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function incrementQueuedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].queuedValidatorKeys++;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].queuedValidatorKeys);
    }

    /**
     * @notice decrease the queued validator count for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function reduceQueuedValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        if (staderPool[_poolId].queuedValidatorKeys == 0) revert NoQueuedValidators();
        staderPool[_poolId].queuedValidatorKeys--;
        emit UpdatedTotalValidatorKeys(_poolId, staderPool[_poolId].queuedValidatorKeys);
    }

    /**
     * @notice increase the registered validator count on beacon chain for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function incrementActiveValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].activeValidatorKeys++;
        emit UpdatedUsedValidatorKeys(_poolId, staderPool[_poolId].activeValidatorKeys);
    }

    /**
     * @notice decrease the registered validator count on beacon chain for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function reduceActiveValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        if (staderPool[_poolId].activeValidatorKeys == 0) revert NoActiveValidators();
        staderPool[_poolId].activeValidatorKeys--;
        emit UpdatedUsedValidatorKeys(_poolId, staderPool[_poolId].activeValidatorKeys);
    }

    /**
     * @notice increase the withdrawn validator count for `_poolId` pool
     * @dev only accept call from stader network pools
     * @param _poolId Id of the pool
     */
    function incrementWithdrawnValidatorKeys(uint8 _poolId) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolId].withdrawnValidatorKeys++;
        emit UpdatedWithdrawnValidatorKeys(_poolId, staderPool[_poolId].withdrawnValidatorKeys);
    }

    /**
     * @notice get the queued validator count which are ready to deposit
     * @dev validator having PRE_DEPOSIT state
     * @param _poolId Id of the pool
     */
    function getQueuedValidator(uint8 _poolId) external view override returns (uint256) {
        return staderPool[_poolId].queuedValidatorKeys;
    }

    /**
     * @notice get the active validator count which are registered on beacon chain
     * @dev validator registered on beacon chain
     * @param _poolId Id of the pool
     */
    function getActiveValidator(uint8 _poolId) external view override returns (uint256) {
        return staderPool[_poolId].activeValidatorKeys;
    }

    /**
     * @notice get the withdrawn validator count which passed the withdrawn epoch
     * @dev validator withdrawn from beacon chain
     * @param _poolId Id of the pool
     */
    function getWithdrawnValidator(uint8 _poolId) external view override returns (uint256) {
        return staderPool[_poolId].activeValidatorKeys;
    }
}
