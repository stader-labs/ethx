pragma solidity ^0.8.16;

import './interfaces/IStaderPoolSelector.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderPoolSelector is IStaderPoolSelector, Initializable, AccessControlUpgradeable {
    uint8 public override exitingPoolCount;
    uint256 public override permissionLessPoolUserDeposit; //TODO not using now, check if required
    bytes32 public constant override POOL_SELECTOR_ADMIN = keccak256('POOL_SELECTOR_ADMIN');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    struct Pool {
        uint8 poolType; // stader defined integer type of pool
        uint8 depositWeight; // deposit weight of pool
        uint8 withdrawWeight; // withdraw weight of pool
        address poolAddress; //pool contract address
        uint256 totalValidatorKeys; //total validator registered in the pool
        uint256 usedValidatorKeys; //validator registered on beacon chain for the pool
        uint256 withdrawnValidatorKeys; // count of validator withdrawn for the pool
    }

    mapping(uint8 => Pool) public override staderPool;
    mapping(uint8 => string) public override poolNameByPoolType;

    /**
     * @notice initialize with permissioned and permissionLess Pool
     * @dev permissionLess pool at index 0
     * @param _poolSelectorAdmin admin address for pool selector
     * @param _permissionedPoolAddress permissioned pool contract address
     * @param _permissionedPoolDepositWeight permissioned pool deposit weight
     * @param _permissionedPoolWithdrawWeight permissioned pool withdraw weight
     * @param _permissionLessPoolAddress permissionLess pool contract address
     * @param _permissionLessPoolDepositWeight permissionLess pool deposit weight
     * @param _permissionLessPoolWithdrawWeight permissionLess pool withdraw weight
     */
    function initialize(
        address _poolSelectorAdmin,
        address _permissionedPoolAddress,
        uint8 _permissionedPoolDepositWeight,
        uint8 _permissionedPoolWithdrawWeight,
        address _permissionLessPoolAddress,
        uint8 _permissionLessPoolDepositWeight,
        uint8 _permissionLessPoolWithdrawWeight
    )
        external
        checkZeroAddress(_poolSelectorAdmin)
        checkZeroAddress(_permissionedPoolAddress)
        checkZeroAddress(_permissionLessPoolAddress)
        initializer
    {
        if (_permissionedPoolDepositWeight + _permissionLessPoolDepositWeight != 100) revert InvalidDepositWeights();
        if (_permissionedPoolWithdrawWeight + _permissionLessPoolWithdrawWeight != 100) revert InvalidWithdrawWeights();
        __AccessControl_init_unchained();
        poolNameByPoolType[0] = 'permissioned';
        poolNameByPoolType[1] = 'permissionLess';
        staderPool[0] = Pool(
            0,
            _permissionLessPoolDepositWeight,
            _permissionLessPoolWithdrawWeight,
            _permissionLessPoolAddress,
            0,
            0,
            0
        );
        staderPool[1] = Pool(
            1,
            _permissionedPoolDepositWeight,
            _permissionedPoolWithdrawWeight,
            _permissionedPoolAddress,
            0,
            0,
            0
        );
        exitingPoolCount = 2;
        permissionLessPoolUserDeposit = 28 ether;
        _grantRole(POOL_SELECTOR_ADMIN, _poolSelectorAdmin);
    }

    /**
     * @notice calculate the Eth to send to each pool based on deposit weight
     * @dev logic according to two pools for phase1
     * @param _pooledEth amount of eth available to deposit
     * @return _poolValidatorShares selected validator count per pool
     */
    function getValidatorPerPoolToDeposit(uint256 _pooledEth)
        external override
        view
        returns (uint256[] memory _poolValidatorShares)
    {
        uint256 availableValidatorOnPermissionLessPool = staderPool[0].totalValidatorKeys -
            staderPool[0].usedValidatorKeys;
        uint256 availableValidatorOnPermissionedPool = staderPool[1].totalValidatorKeys -
            staderPool[1].usedValidatorKeys;
        uint256 requiredValidatorToDeposit = _pooledEth / 32 ether;
        if (availableValidatorOnPermissionLessPool == 0 && availableValidatorOnPermissionedPool == 0)
            revert ValidatorsNotAvailable();
        if (requiredValidatorToDeposit == 1) {
            uint256 permissionLessPoolValidators = staderPool[0].usedValidatorKeys >= staderPool[1].usedValidatorKeys
                ? 1
                : 0;
            uint256 permissionedPoolValidators = staderPool[0].usedValidatorKeys >= staderPool[1].usedValidatorKeys
                ? 0
                : 1;
            _poolValidatorShares[0] = permissionLessPoolValidators;
            _poolValidatorShares[1] = permissionedPoolValidators;
            return _poolValidatorShares;
        } else {
            uint256 permissionLessPoolValidators = (requiredValidatorToDeposit * staderPool[0].depositWeight) / 100;
            permissionLessPoolValidators = availableValidatorOnPermissionLessPool >= permissionLessPoolValidators
                ? permissionLessPoolValidators
                : availableValidatorOnPermissionLessPool;
            uint256 permissionedPoolValidators = requiredValidatorToDeposit - permissionLessPoolValidators;
            permissionedPoolValidators = availableValidatorOnPermissionedPool >= permissionedPoolValidators
                ? permissionedPoolValidators
                : availableValidatorOnPermissionedPool;
            _poolValidatorShares[0] = permissionLessPoolValidators;
            _poolValidatorShares[1] = permissionedPoolValidators;
            return _poolValidatorShares;
        }
    }

    /**
     * @notice add a new pool in pool selector logic
     * @dev pass all previous pool new updated weights, only callable by admin
     * @param _newPoolName name of new pool
     * @param _newPoolAddress new pool contract address
     * @param _newDepositWeights updated deposit weights of all pools including new one
     * @param _newWithdrawWeights updated withdraw weights of all pools including new one
     */
    function addNewPool(
        string calldata _newPoolName,
        address _newPoolAddress,
        uint8[] calldata _newDepositWeights,
        uint8[] calldata _newWithdrawWeights
    ) external override checkZeroAddress(_newPoolAddress) onlyRole(POOL_SELECTOR_ADMIN) {
        if (exitingPoolCount != _newDepositWeights.length + 1 || exitingPoolCount != _newWithdrawWeights.length + 1)
            revert InvalidNewPoolInput();
        poolNameByPoolType[exitingPoolCount] = _newPoolName;
        uint8 totalDepositWeight = _newDepositWeights[exitingPoolCount];
        uint256 totalWithdrawWeight = _newDepositWeights[exitingPoolCount];
        for (uint8 i = 0; i < exitingPoolCount; i++) {
            staderPool[i].depositWeight = _newDepositWeights[i];
            staderPool[i].withdrawWeight = _newWithdrawWeights[i];
            totalDepositWeight += _newDepositWeights[i];
            totalWithdrawWeight += _newWithdrawWeights[i];
        }
        if (totalDepositWeight != 100 || totalWithdrawWeight != 100) revert InvalidNewPoolInput();
        staderPool[exitingPoolCount] = Pool(
            exitingPoolCount,
            _newDepositWeights[exitingPoolCount],
            _newWithdrawWeights[exitingPoolCount],
            _newPoolAddress,
            0,
            0,
            0
        );
        exitingPoolCount++;
    }

    /**
     * @notice updated the deposit weights of existing pools
     * @dev only admin can call
     * @param _newDepositWeights new deposit weights of pools
     */
    function updateExistingDepositWeights(uint8[] calldata _newDepositWeights) external override onlyRole(POOL_SELECTOR_ADMIN) {
        if (exitingPoolCount != _newDepositWeights.length) revert InvalidExistingWeightUpdateInput();
        uint8 totalDepositWeight;
        for (uint8 i = 0; i < exitingPoolCount; i++) {
            totalDepositWeight += _newDepositWeights[i];
            staderPool[i].depositWeight = _newDepositWeights[i];
        }
        if (totalDepositWeight != 100) revert InvalidDepositWeights();
    }

    /**
     * @notice updated the withdraw weights of existing pools
     * @dev only admin can call
     * @param _newWithdrawWeights new withdraw weights of pools
     */
    function updateExistingWithdrawWeights(uint8[] calldata _newWithdrawWeights)
        external override
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        if (exitingPoolCount != _newWithdrawWeights.length) revert InvalidExistingWeightUpdateInput();
        uint8 totalWithdrawWeight;
        for (uint8 i = 0; i < exitingPoolCount; i++) {
            totalWithdrawWeight += _newWithdrawWeights[i];
            staderPool[i].withdrawWeight = _newWithdrawWeights[i];
        }
        if (totalWithdrawWeight != 100) revert InvalidWithdrawWeights();
    }

    /**
     * @notice updated the withdraw weights of existing pools
     * @dev only admin can call
     * @param _poolType new withdraw weights of pools
     * @param _poolAddress updated address of the pool
     */
    function updatePoolAddress(uint8 _poolType, address _poolAddress)
        external override
        checkZeroAddress(_poolAddress)
        onlyRole(POOL_SELECTOR_ADMIN)
    {
        if (_poolType >= exitingPoolCount) revert InvalidPoolType();
        staderPool[_poolType].poolAddress = _poolAddress;
    }

    /**
     * @notice increase the registered validator count for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolType type of the pool
     */
    function updateTotalValidatorKeys(uint8 _poolType) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolType].totalValidatorKeys++;
        emit UpdatedTotalValidatorKeys(_poolType, staderPool[_poolType].totalValidatorKeys);
    }

    /**
     * @notice increase the registered validator count on beacon chain for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolType type of the pool
     */
    function updateUsedValidatorKeys(uint8 _poolType) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolType].usedValidatorKeys++;
        emit UpdatedUsedValidatorKeys(_poolType, staderPool[_poolType].usedValidatorKeys);
    }

    /**
     * @notice increase the withdrawn validator count for `_poolType` pool
     * @dev only accept call from stader network pools
     * @param _poolType type of the pool
     */
    function updateWithdrawnValidatorKeys(uint8 _poolType) external override onlyRole(STADER_NETWORK_POOL) {
        staderPool[_poolType].withdrawnValidatorKeys++;
        emit UpdatedWithdrawnValidatorKeys(_poolType, staderPool[_poolType].withdrawnValidatorKeys);
    }

    /**
     * @notice update the userDeposit for permissionLess pool
     * @dev only admin can call
     * @param _newUserDeposit new value of user deposit amount
     */
    function updatePermissionLessPoolUserDeposit(uint256 _newUserDeposit) external override onlyRole(POOL_SELECTOR_ADMIN) {
        permissionLessPoolUserDeposit = _newUserDeposit;
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
