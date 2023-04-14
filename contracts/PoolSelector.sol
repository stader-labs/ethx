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

    uint16 public poolAllocationMaxSize; //TODO need to decide if we need
    IStaderConfig public staderConfig;
    uint256 public poolIdArrayIndexForExcessDeposit;
    uint256 public constant POOL_WEIGHTS_SUM = 10000;

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

        poolAllocationMaxSize = 100;
        staderConfig = IStaderConfig(_staderConfig);
        poolWeights[1] = _permissionlessTarget;
        poolWeights[2] = _permissionedTarget;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice calculates the count of validator to deposit on beacon chain for a pool based on target weight and supply
     * @param _newValidatorToRegister new validator that can be deposited for pool `_poolId` based on supply
     * @return selectedPoolCapacity validator count to deposit for pool
     */
    function computePoolAllocationForDeposit(uint8 _poolId, uint256 _newValidatorToRegister)
        external
        view
        override
        returns (uint256 selectedPoolCapacity)
    {
        IPoolUtils poolUtils = IPoolUtils(staderConfig.getPoolUtils());
        uint8[] memory poolIdArray = poolUtils.getPoolIdArray();
        uint256 poolCount = poolIdArray.length;

        uint256 activeValidatorCount;
        for (uint256 i = 0; i < poolCount; i++) {
            activeValidatorCount += (poolUtils.getActiveValidatorCountByPool(poolIdArray[i]));
        }
        uint256 totalValidatorsRequired = (activeValidatorCount + _newValidatorToRegister);
        uint256 remainingPoolCapacity = poolUtils.getQueuedValidatorCountByPool(_poolId);
        uint256 currentActiveValidators = poolUtils.getActiveValidatorCountByPool(_poolId);
        uint256 poolTotalTarget = (poolWeights[_poolId] * totalValidatorsRequired) / POOL_WEIGHTS_SUM;
        (, uint256 remainingPoolTarget) = SafeMath.trySub(poolTotalTarget, currentActiveValidators);
        //
        selectedPoolCapacity = Math.min(poolAllocationMaxSize, Math.min(remainingPoolCapacity, remainingPoolTarget));
    }

    /**
     * @notice allocate pool wise validator count to deposit for excess supply starting from `poolIdArrayIndexForExcessDeposit`
     * @dev only stader stake pool manager contract can call, update the `poolIdArrayIndexForExcessDeposit` for next cycle calculation
     * @param _excessETHAmount amount of excess ETH ready to stake on beacon chain
     * @return selectedPoolCapacity array of pool wise validator count to deposit
     * @return poolIdArray array of poolIDs
     */
    function poolAllocationForExcessETHDeposit(uint256 _excessETHAmount)
        external
        override
        returns (uint256[] memory selectedPoolCapacity, uint8[] memory poolIdArray)
    {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STAKE_POOL_MANAGER());
        IPoolUtils poolUtils = IPoolUtils(staderConfig.getPoolUtils());
        poolIdArray = poolUtils.getPoolIdArray();
        uint256 poolCount = poolIdArray.length;
        uint256 ETH_PER_NODE = staderConfig.getStakedEthPerNode();
        selectedPoolCapacity = new uint256[](poolCount);

        uint256 i = poolIdArrayIndexForExcessDeposit;
        for (uint256 j = 0; j < poolCount; j++) {
            uint256 poolCapacity = poolUtils.getQueuedValidatorCountByPool(poolIdArray[i]);
            uint256 poolDepositSize = ETH_PER_NODE - poolUtils.getCollateralETH(poolIdArray[i]);
            uint256 remainingValidatorsToDeposit = _excessETHAmount / poolDepositSize;
            selectedPoolCapacity[i] = Math.min(poolCapacity, remainingValidatorsToDeposit);
            _excessETHAmount -= selectedPoolCapacity[i] * poolDepositSize;
            i = (i + 1) % poolCount;
            //For _excessETHAmount < ETH_PER_NODE, we will be able to at best deposit one more validator
            //but that will introduce complex logic, hence we are not solving that
            if (_excessETHAmount < ETH_PER_NODE) {
                poolIdArrayIndexForExcessDeposit = i;
                break;
            }
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
        poolAllocationMaxSize = _poolAllocationMaxSize;
        emit UpdatedPoolAllocationMaxSize(_poolAllocationMaxSize);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
