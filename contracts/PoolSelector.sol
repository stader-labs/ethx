// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolSelector is IPoolSelector, Initializable, AccessControlUpgradeable {
    using Math for uint256;

    uint8 public poolIdForExcessDeposit;
    uint8 public constant TOTAL_TARGET = 100;
    uint16 public BATCH_LIMIT;

    address public poolFactoryAddress;

    uint256 public constant DEPOSIT_SIZE = 32 ether;

    mapping(uint8 => uint256) public poolTargets;

    bytes32 public constant override POOL_SELECTOR_ADMIN = keccak256('POOL_SELECTOR_ADMIN');
    bytes32 public constant override STADER_STAKE_POOL_MANAGER = keccak256('STADER_STAKE_POOL_MANAGER');

    /**
     * @notice initialize with permissioned and permissionless Pool
     * @dev pool index start from 1 with permission less pool
     * @param _permissionlessTarget target weight of permissionless pool
     * @param _adminOwner admin address for pool selector
     * @param _poolFactoryAddress address for poolFactory contract
     */
    function initialize(
        uint8 _permissionlessTarget,
        uint8 _permissionedTarget,
        address _adminOwner,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        if (_permissionlessTarget + _permissionedTarget != TOTAL_TARGET) revert InvalidTargetWeight();

        __AccessControl_init_unchained();

        poolIdForExcessDeposit = 1;
        BATCH_LIMIT = 100;
        poolFactoryAddress = _poolFactoryAddress;
        poolTargets[1] = _permissionlessTarget;
        poolTargets[2] = _permissionedTarget;

        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice calculates the amount of validator number to be deposited on beacon chain based on target weight
     * @dev first loop allot validators to match the target share with the constraint of capacity and
     * second loop uses sequential looping over all pool starting from a particular poolId and keep on exhausting the capacity
     * and updating the starting poolId for next iteration
     * * all array start with index 1
     * @param _pooledEth amount of eth ready to deposit on pool manager
     */
    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        override
        onlyRole(STADER_STAKE_POOL_MANAGER)
        returns (uint256[] memory selectedPoolCapacity)
    {
        uint8 poolCount = IPoolFactory(poolFactoryAddress).poolCount();

        uint256 depositedETh;
        for (uint8 i = 1; i <= IPoolFactory(poolFactoryAddress).poolCount(); i++) {
            depositedETh += (IPoolFactory(poolFactoryAddress).getActiveValidatorCountByPool(i)) * DEPOSIT_SIZE;
        }
        uint256 totalEth = depositedETh + _pooledEth;
        uint256 totalValidatorsRequired = totalEth / DEPOSIT_SIZE;
        // new validators to register on beacon chain with `_pooledEth` taking `BATCH_LIMIT` into consideration
        uint256 newValidatorsToDeposit = Math.min(BATCH_LIMIT, _pooledEth / DEPOSIT_SIZE);
        // `poolCapacity` array start with index 1

        selectedPoolCapacity = new uint256[](poolCount + 1);
        uint256[] memory remainingPoolCapacity = new uint256[](poolCount + 1);

        uint256 validatorSpunCount;
        for (
            uint8 i = 1;
            i <= IPoolFactory(poolFactoryAddress).poolCount() && validatorSpunCount < newValidatorsToDeposit;
            i++
        ) {
            remainingPoolCapacity[i] = IPoolFactory(poolFactoryAddress).getQueuedValidatorCountByPool(i);
            uint256 currentActiveValidators = IPoolFactory(poolFactoryAddress).getActiveValidatorCountByPool(i);
            uint256 poolTotalTarget = (poolTargets[i] * totalValidatorsRequired) / 100;
            selectedPoolCapacity[i] = Math.min(
                Math.min(remainingPoolCapacity[i], poolTotalTarget - currentActiveValidators),
                newValidatorsToDeposit - validatorSpunCount
            );
            remainingPoolCapacity[i] -= selectedPoolCapacity[i];
            validatorSpunCount += selectedPoolCapacity[i];
        }

        // check for more validators to deposit and select pool with excess supply in a sequential order
        // and update the starting index of pool for next sequence after every iteration
        if (validatorSpunCount < newValidatorsToDeposit) {
            uint256 remainingValidatorsToDeposit = newValidatorsToDeposit - validatorSpunCount;
            uint8[] memory poolQueue = new uint8[](IPoolFactory(poolFactoryAddress).poolCount());
            uint8 counter;
            for (uint8 i = poolIdForExcessDeposit; i <= IPoolFactory(poolFactoryAddress).poolCount(); i++) {
                poolQueue[counter++] = i;
            }
            for (uint8 i = 1; i < poolIdForExcessDeposit; i++) {
                poolQueue[counter++] = i;
            }
            for (uint8 i = 0; i < poolQueue.length; i++) {
                uint256 newSelectedCapacity = Math.min(
                    remainingPoolCapacity[poolQueue[i]],
                    remainingValidatorsToDeposit
                );
                selectedPoolCapacity[poolQueue[i]] += newSelectedCapacity;
                remainingValidatorsToDeposit -= newSelectedCapacity;
                // Don't have to update poolID if the `remainingValidatorsToDeposit` does not become 0
                // As we have scanned through all pool, will start from same pool in same iteration
                if (remainingValidatorsToDeposit == 0) {
                    poolIdForExcessDeposit = poolQueue[(i + 1) % poolQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice update the target weights of existing pools
     * @dev only admin can call
     * @param _poolTargets new target weights of pools
     */
    function updatePoolWeights(uint8[] calldata _poolTargets) external onlyRole(POOL_SELECTOR_ADMIN) {
        if (IPoolFactory(poolFactoryAddress).poolCount() != _poolTargets.length) revert InvalidNewTargetInput();

        uint8 totalTarget;
        for (uint8 i = 0; i < _poolTargets.length; i++) {
            totalTarget += _poolTargets[i];
            if (totalTarget > TOTAL_TARGET) revert InvalidNewTargetInput();
            poolTargets[i + 1] = _poolTargets[i];
        }
        if (totalTarget != TOTAL_TARGET) revert InvalidSumOfPoolTargets();
    }

    function updateBatchLimit(uint16 _batchLimit) external onlyRole(POOL_SELECTOR_ADMIN) {
        BATCH_LIMIT = _batchLimit;
    }
}
