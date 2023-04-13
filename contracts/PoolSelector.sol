// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolUtils.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolSelector is IPoolSelector, Initializable, AccessControlUpgradeable {
    using Math for uint256;
    using SafeMath for uint256;

    uint16 public POOL_ALLOCATION_MAX_SIZE;
    IStaderConfig public staderConfig;
    uint256 public poolIdArrayIndexForExcessDeposit;
    uint256 public constant POOL_WEIGHTS_SUM = 10000;

    //TODO make sure weight are in order of pool Id
    mapping(uint8 => uint256) public poolWeights;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initialize with permissionless and permissioned Pool weights
     * @dev pool index start from 1 with permission less pool
     * @param _admin admin address for this contract
     * @param _staderConfig config contract address
     * @param _permissionlessTarget target weight of permissionless pool
     * @param _permissionedTarget target weight of permissioned pool
     */
    function initialize(
        address _admin,
        address _staderConfig,
        uint256 _permissionlessTarget,
        uint256 _permissionedTarget
    ) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        if (_permissionlessTarget + _permissionedTarget != POOL_WEIGHTS_SUM) {
            revert InvalidTargetWeight();
        }

        __AccessControl_init_unchained();

        POOL_ALLOCATION_MAX_SIZE = 100;
        staderConfig = IStaderConfig(_staderConfig);
        poolWeights[1] = _permissionlessTarget;
        poolWeights[2] = _permissionedTarget;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice calculates the amount of validator number to be deposited on beacon chain based on target weight
     * @dev first loop allot validators to match the target share with the constraint of capacity and
     * second loop uses sequential looping over all pool starting from a particular poolId and keep on exhausting the capacity
     * and updating the starting poolId for next iteration
     * @param _pooledEth amount of eth ready to deposit on pool manager
     */
    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        override
        returns (uint256[] memory selectedPoolCapacity, uint8[] memory poolIdArray)
    {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STAKE_POOL_MANAGER());
        address poolUtilsAddress = staderConfig.getPoolUtils();
        uint256 ETH_PER_NODE = staderConfig.getStakedEthPerNode();

        poolIdArray = IPoolUtils(poolUtilsAddress).getPoolIdArray();
        uint256 poolCount = poolIdArray.length;

        uint256 depositedETh;
        for (uint256 i = 0; i < poolCount; i++) {
            depositedETh += (IPoolUtils(poolUtilsAddress).getActiveValidatorCountByPool(poolIdArray[i])) * ETH_PER_NODE;
        }
        uint256 totalValidatorsRequired = (depositedETh + _pooledEth) / ETH_PER_NODE;
        // new validators to register on beacon chain with `_pooledEth` taking `POOL_ALLOCATION_MAX_SIZE` into consideration
        uint256 newValidatorsToDeposit = Math.min(POOL_ALLOCATION_MAX_SIZE, _pooledEth / ETH_PER_NODE);

        selectedPoolCapacity = new uint256[](poolCount);
        uint256[] memory remainingPoolCapacity = new uint256[](poolCount);

        uint256 validatorSpunCount;
        for (uint256 i = 0; i < poolCount && validatorSpunCount < newValidatorsToDeposit; i++) {
            remainingPoolCapacity[i] = IPoolUtils(poolUtilsAddress).getQueuedValidatorCountByPool(poolIdArray[i]);
            uint256 currentActiveValidators = IPoolUtils(poolUtilsAddress).getActiveValidatorCountByPool(
                poolIdArray[i]
            );
            uint256 poolTotalTarget = (poolWeights[poolIdArray[i]] * totalValidatorsRequired) / POOL_WEIGHTS_SUM;
            (, uint256 remainingPoolTarget) = SafeMath.trySub(poolTotalTarget, currentActiveValidators);
            selectedPoolCapacity[i] = Math.min(
                Math.min(remainingPoolCapacity[i], remainingPoolTarget),
                newValidatorsToDeposit - validatorSpunCount
            );
            remainingPoolCapacity[i] -= selectedPoolCapacity[i];
            validatorSpunCount += selectedPoolCapacity[i];
        }

        // check for more validators to deposit and select pool with excess supply in a sequential order
        // and update the starting index of pool for next sequence after every iteration
        if (validatorSpunCount < newValidatorsToDeposit) {
            uint256 remainingValidatorsToDeposit = newValidatorsToDeposit - validatorSpunCount;
            uint256 i = poolIdArrayIndexForExcessDeposit;
            //if some pool gets deactivate, reset the index of poolIdArray for excess deposit
            //if index greater or equal to poolCount
            if (i >= poolCount) {
                i = 0;
            }
            do {
                uint256 newSelectedCapacity = Math.min(remainingPoolCapacity[i], remainingValidatorsToDeposit);
                selectedPoolCapacity[i] += newSelectedCapacity;
                remainingValidatorsToDeposit -= newSelectedCapacity;
                // Don't have to update poolID if the `remainingValidatorsToDeposit` does not become 0
                // As we have scanned through all pool, will start from same pool in same iteration
                i = (i + 1) % poolCount;
                if (remainingValidatorsToDeposit == 0) {
                    poolIdArrayIndexForExcessDeposit = i;
                    break;
                }
            } while (i != poolIdArrayIndexForExcessDeposit);
        }
    }

    /**
     * @notice update the target weights of existing pools
     * @dev only `Manager` can call
     * @param _poolTargets new target weights of pools
     */
    function updatePoolWeights(uint256[] calldata _poolTargets) external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        uint8[] memory poolIdArray = IPoolUtils(staderConfig.getPoolUtils()).getPoolIdArray();
        uint256 poolCount = poolIdArray.length;
        uint256 poolTargetLength = _poolTargets.length;

        if (poolCount != poolTargetLength) {
            revert InvalidNewTargetInput();
        }

        uint256 totalWeight;
        for (uint256 i = 0; i < poolTargetLength; i++) {
            totalWeight += _poolTargets[i];
            poolWeights[poolIdArray[i]] = _poolTargets[i];
            emit UpdatedPoolWeight(poolIdArray[i], _poolTargets[i]);
        }
        if (totalWeight != POOL_WEIGHTS_SUM) {
            revert InvalidSumOfPoolWeights();
        }
    }

    function updatePoolAllocationMaxSize(uint16 _poolAllocationMaxSize) external {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        POOL_ALLOCATION_MAX_SIZE = _poolAllocationMaxSize;
        emit UpdatedPoolAllocationMaxSize(_poolAllocationMaxSize);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
