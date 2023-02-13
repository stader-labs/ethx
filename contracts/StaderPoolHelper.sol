pragma solidity ^0.8.16;

import './interfaces/IStaderPoolHelper.sol';
import './library/Address.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderPoolHelper is IStaderPoolHelper, Initializable, AccessControlUpgradeable {
    
    using Math for uint256;

    uint8 public override poolCount;
    uint8 public poolIdForExcessSupply;
    uint16 public maxValidatorPerBlock;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    bytes32 public constant override POOL_SELECTOR_ADMIN = keccak256('POOL_SELECTOR_ADMIN');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    struct Pool {
        uint8 targetShare; // shares of total active validators for the pool
        string poolName; // pool name
        address poolAddress; //pool contract address
        address operatorRegistry; //address of operator registry
        address validatorRegistry; // address of validator registry
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
     * @param _permissionLessOperatorRegistry permissionLess operator registry
     * @param _permissionLessValidatorRegistry permissionLess validator registry
     */
    function initialize(
        uint8 _permissionLessTarget,
        address _adminOwner,
        address _permissionLessPoolAddress,
        address _permissionLessOperatorRegistry,
        address _permissionLessValidatorRegistry
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_permissionLessPoolAddress);
        Address.checkNonZeroAddress(_permissionLessOperatorRegistry);
        Address.checkNonZeroAddress(_permissionLessValidatorRegistry);
        __AccessControl_init_unchained();
        staderPool[1] = Pool(
            _permissionLessTarget,
            'PERMISSIONLESS',
            _permissionLessPoolAddress,
            _permissionLessOperatorRegistry,
            _permissionLessValidatorRegistry,
            0,
            0,
            0,
            0
        );
        poolCount = 1;
        poolIdForExcessSupply =1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice add a new pool in pool selector logic
     * @dev pass all previous pool new updated weights, only callable by admin
     * @param _newTargetShares new targets for all pool including new
     * @param _newPoolName name of new pool
     * @param _newPoolAddress new pool contract address
     * @param _operatorRegistry operator registry of the new pool
     * @param _validatorRegistry validator registry of new pool
     */
    function addNewPool(
        uint8[] calldata _newTargetShares,
        string calldata _newPoolName,
        address _newPoolAddress,
        address _operatorRegistry,
        address _validatorRegistry
    ) external override onlyRole(POOL_SELECTOR_ADMIN) {
        Address.checkNonZeroAddress(_newPoolAddress);
        if (poolCount + 1 != _newTargetShares.length) revert InvalidNewPoodInput();
        uint8 totalTarget;
        for (uint8 i = 1; i < _newTargetShares.length; i++) {
            totalTarget += _newTargetShares[i - 1];
            if(totalTarget > 100) revert InvalidNewTargetInput();
            staderPool[i].targetShare = _newTargetShares[i - 1];
        }
        staderPool[poolCount + 1] = Pool(
            _newTargetShares[poolCount],
            _newPoolName,
            _newPoolAddress,
            _operatorRegistry,
            _validatorRegistry,
            0,
            0,
            0,
            0
        );
        poolCount++;
    }

    /**
     * @notice calculates the amount of Eth for each value based on target
     * @param _pooledEth amount of eth ready to deposit on pool manager
\     */
    function delegateToPool(uint256 _pooledEth) external returns(uint256[] memory validatorsToSpin){
        uint256 depositedETh;
        for(uint8 i =0;i<=poolCount;i++){
            depositedETh += (staderPool[i].activeValidatorKeys)* DEPOSIT_SIZE;
        }
        uint256 totalEth = depositedETh + _pooledEth;
        uint256 totalValidatorsRequired = totalEth/DEPOSIT_SIZE ;
        uint256 newValidatorToSpin = _pooledEth/DEPOSIT_SIZE;
        uint256[] memory validatorCapacity;
        uint256 validatorSpunCount;
        for(uint8 i =1; i<=poolCount && validatorSpunCount<maxValidatorPerBlock; i++){
            validatorCapacity[i] = staderPool[i].queuedValidatorKeys;
            uint256 currentActiveValidators = staderPool[i].activeValidatorKeys;
            uint256 poolTotalTarget = (staderPool[i].targetShare*totalValidatorsRequired)/100 ;
            validatorsToSpin[i-1] = Math.min(Math.min(validatorCapacity[i],poolTotalTarget-currentActiveValidators),maxValidatorPerBlock-validatorSpunCount);
            validatorCapacity[i] -= validatorsToSpin[i-1];
            validatorSpunCount += validatorsToSpin[i-1];
            newValidatorToSpin -= validatorsToSpin[i-1];
            if(newValidatorToSpin == 0) break;
        }

        if(validatorSpunCount <maxValidatorPerBlock && validatorSpunCount <totalValidatorsRequired){

            uint256 totalExcessValidatorCount = Math.min(maxValidatorPerBlock-validatorSpunCount, newValidatorToSpin);
            uint8[] memory poolQueue ;
            uint8 counter;
            for(uint8 i=poolIdForExcessSupply;i<=poolCount;i++){
                poolQueue[counter++] = i;
            }
            for(uint8 i=1;i<poolIdForExcessSupply;i++){
                poolQueue[counter++] = i;
            }
            for(uint8 i = 0;i<=poolQueue.length;i++){
                uint256 extraValidatorToSpin = Math.min(Math.min(validatorCapacity[poolQueue[i]],totalExcessValidatorCount),maxValidatorPerBlock-validatorSpunCount);
                validatorsToSpin[poolQueue[i]] += extraValidatorToSpin;
                totalExcessValidatorCount -= extraValidatorToSpin;
                if(totalExcessValidatorCount ==0){
                    poolIdForExcessSupply = poolQueue[(i+1)%poolQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice updated the pool address for pool `_poolId`
     * @dev only admin can call
     * @param _poolId Id of the pool
     * @param _poolAddress updated address of the pool
     */
    function updatePoolAddress(uint8 _poolId, address _poolAddress) external override onlyRole(POOL_SELECTOR_ADMIN) {
        Address.checkNonZeroAddress(_poolAddress);
        if (_poolId > poolCount) revert InvalidPoolId();
        staderPool[_poolId].poolAddress = _poolAddress;
    }

    /**
     * @notice updated the operator registry address for pool `_poolId`
     * @dev only admin can call
     * @param _poolId Id of the pool
     * @param _operatorRegistry updated operator registry address for the pool
     */
    function updatePoolOperatorRegistry(uint8 _poolId, address _operatorRegistry)
        external
        override
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        Address.checkNonZeroAddress(_operatorRegistry);
        if (_poolId > poolCount) revert InvalidPoolId();
        staderPool[_poolId].operatorRegistry = _operatorRegistry;
    }

    /**
     * @notice updated the validator registry address for pool `_poolId`
     * @dev only admin can call
     * @param _poolId Id of the pool
     * @param _validatorRegistry updated validator registry address for the pool
     */
    function updatePoolValidatorRegistry(uint8 _poolId, address _validatorRegistry)
        external
        override
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        Address.checkNonZeroAddress(_validatorRegistry);
        if (_poolId > poolCount) revert InvalidPoolId();
        staderPool[_poolId].validatorRegistry = _validatorRegistry;
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
