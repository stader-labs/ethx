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

    uint8 public poolIdForExcessDeposit;
    uint16 public POOL_ALLOCATION_MAX_SIZE;

    IStaderConfig public staderConfig;
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

        poolIdForExcessDeposit = 1;
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
     * * all array start with index 1
     * @param _pooledEth amount of eth ready to deposit on pool manager
     */
    function computePoolAllocationForDeposit(uint256 _pooledEth)
        external
        override
        returns (uint256[] memory selectedPoolCapacity)
    {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STAKE_POOL_MANAGER());
        address poolUtilsAddress = staderConfig.getPoolUtils();
        uint256 ETH_PER_NODE = staderConfig.getStakedEthPerNode();
        uint8 poolCount = IPoolUtils(poolUtilsAddress).poolCount();

        uint256 depositedETh;
        for (uint8 i = 1; i <= poolCount; i++) {
            depositedETh += (IPoolUtils(poolUtilsAddress).getActiveValidatorCountByPool(i)) * ETH_PER_NODE;
        }
        uint256 totalEth = depositedETh + _pooledEth;
        uint256 totalValidatorsRequired = totalEth / ETH_PER_NODE;
        // new validators to register on beacon chain with `_pooledEth` taking `POOL_ALLOCATION_MAX_SIZE` into consideration
        uint256 newValidatorsToDeposit = Math.min(POOL_ALLOCATION_MAX_SIZE, _pooledEth / ETH_PER_NODE);
        // `poolCapacity` array start with index 1

        selectedPoolCapacity = new uint256[](poolCount + 1);
        uint256[] memory remainingPoolCapacity = new uint256[](poolCount + 1);

        uint256 validatorSpunCount;
        for (uint8 i = 1; i <= poolCount && validatorSpunCount < newValidatorsToDeposit; i++) {
            remainingPoolCapacity[i] = IPoolUtils(poolUtilsAddress).getQueuedValidatorCountByPool(i);
            uint256 currentActiveValidators = IPoolUtils(poolUtilsAddress).getActiveValidatorCountByPool(i);
            uint256 poolTotalTarget = (poolWeights[i] * totalValidatorsRequired) / POOL_WEIGHTS_SUM;
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
            uint8 i = poolIdForExcessDeposit;
            do {
                uint256 newSelectedCapacity = Math.min(remainingPoolCapacity[i], remainingValidatorsToDeposit);
                selectedPoolCapacity[i] += newSelectedCapacity;
                remainingValidatorsToDeposit -= newSelectedCapacity;
                // Don't have to update poolID if the `remainingValidatorsToDeposit` does not become 0
                // As we have scanned through all pool, will start from same pool in same iteration
                i = (i % poolCount) + 1;
                if (remainingValidatorsToDeposit == 0) {
                    poolIdForExcessDeposit = i;
                    break;
                }
            } while (i != poolIdForExcessDeposit);
        }
    }

    /**
     * @notice update the target weights of existing pools
     * @dev only admin can call
     * @param _poolTargets new target weights of pools
     */
    function updatePoolWeights(uint8[] calldata _poolTargets) external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        if (IPoolUtils(staderConfig.getPoolUtils()).poolCount() != _poolTargets.length) {
            revert InvalidNewTargetInput();
        }

        uint8 totalWeight;
        for (uint8 i = 0; i < _poolTargets.length; i++) {
            totalWeight += _poolTargets[i];
            poolWeights[i + 1] = _poolTargets[i];
            emit UpdatedPoolWeight(i + 1, _poolTargets[i]);
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
