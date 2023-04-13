// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IPoolUtils.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolUtils is IPoolUtils, Initializable, AccessControlUpgradeable {
    mapping(uint8 => Pool) public override pools;

    uint8 public override poolCount;
    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;
    IStaderConfig public staderConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) public initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        staderConfig = IStaderConfig(_staderConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Add a new pool.
     * @dev This function should only be called by the `MANAGER` role
     * @param _poolName The name of the new pool.
     * @param _poolAddress The address of the new pool contract.
     */
    //TODO sanjay make sure pools are added in same order of poolId
    function addNewPool(string calldata _poolName, address _poolAddress) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        if (bytes(_poolName).length == 0) {
            revert EmptyString();
        }
        UtilLib.checkNonZeroAddress(_poolAddress);

        pools[poolCount + 1] = Pool({poolName: _poolName, poolAddress: _poolAddress});
        poolCount++;

        emit PoolAdded(_poolName, _poolAddress);
    }

    /**
     * @notice Update the address of a pool.
     * @dev This function should only be called by the `DEFAULT_ADMIN_ROLE` role
     * @param _poolId The ID of the pool to update.
     * @param _newPoolAddress The updated address of the pool.
     */
    function updatePoolAddress(uint8 _poolId, address _newPoolAddress)
        external
        override
        validPoolId(_poolId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UtilLib.checkNonZeroAddress(_newPoolAddress);
        pools[_poolId].poolAddress = _newPoolAddress;
        emit PoolAddressUpdated(_poolId, _newPoolAddress);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /// @inheritdoc IPoolUtils
    function getProtocolFee(uint8 _poolId) public view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).protocolFee();
    }

    /// @inheritdoc IPoolUtils
    function getOperatorFee(uint8 _poolId) public view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).operatorFee();
    }

    /// @inheritdoc IPoolUtils
    function getTotalActiveValidatorCount() public view override returns (uint256) {
        uint256 totalActiveValidatorCount;
        for (uint8 i = 1; i <= poolCount; i++) {
            totalActiveValidatorCount += getActiveValidatorCountByPool(i);
        }

        return totalActiveValidatorCount;
    }

    /// @inheritdoc IPoolUtils
    function getQueuedValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalQueuedValidatorCount();
    }

    /// @inheritdoc IPoolUtils
    function getActiveValidatorCountByPool(uint8 _poolId) public view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalActiveValidatorCount();
    }

    /// @inheritdoc IPoolUtils
    function retrieveValidator(bytes calldata _pubkey) public view override returns (Validator memory) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (getValidatorByPool(i, _pubkey).pubkey.length == 0) {
                continue;
            }
            return getValidatorByPool(i, _pubkey);
        }
        Validator memory emptyValidator;

        return emptyValidator;
    }

    /// @inheritdoc IPoolUtils
    function getValidatorByPool(uint8 _poolId, bytes calldata _pubkey)
        public
        view
        override
        validPoolId(_poolId)
        returns (Validator memory)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getValidator(_pubkey);
    }

    /// @inheritdoc IPoolUtils
    function retrieveOperator(bytes calldata _pubkey) public view override returns (Operator memory) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (getValidatorByPool(i, _pubkey).pubkey.length == 0) {
                continue;
            }
            return getOperator(i, _pubkey);
        }

        Operator memory emptyOperator;
        return emptyOperator;
    }

    /// @inheritdoc IPoolUtils
    function getOperator(uint8 _poolId, bytes calldata _pubkey)
        public
        view
        override
        validPoolId(_poolId)
        returns (Operator memory)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getOperator(_pubkey);
    }

    /// @inheritdoc IPoolUtils
    function getSocializingPoolAddress(uint8 _poolId) public view override validPoolId(_poolId) returns (address) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getSocializingPoolAddress();
    }

    /// @inheritdoc IPoolUtils
    function getOperatorTotalNonTerminalKeys(
        uint8 _poolId,
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) public view override validPoolId(_poolId) returns (uint256) {
        return
            IStaderPoolBase(pools[_poolId].poolAddress).getOperatorTotalNonTerminalKeys(
                _nodeOperator,
                _startIndex,
                _endIndex
            );
    }

    function getCollateralETH(uint8 _poolId) public view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getCollateralETH();
    }

    function getNodeRegistry(uint8 _poolId) external view override validPoolId(_poolId) returns (address) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getNodeRegistry();
    }

    function isExistingPubkey(bytes calldata _pubkey) public view override returns (bool) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (IStaderPoolBase(pools[i].poolAddress).isExistingPubkey(_pubkey)) {
                return true;
            }
        }
        return false;
    }

    function isExistingOperator(address _operAddr) external view override returns (bool) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (IStaderPoolBase(pools[i].poolAddress).isExistingOperator(_operAddr)) {
                return true;
            }
        }
        return false;
    }

    function getOperatorPoolId(address _operAddr) external view override returns (uint8) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (IStaderPoolBase(pools[i].poolAddress).isExistingOperator(_operAddr)) {
                return i;
            }
        }
        revert OperatorIsNotOnboarded();
    }

    function getValidatorPoolId(bytes calldata _pubkey) external view override returns (uint8) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (IStaderPoolBase(pools[i].poolAddress).isExistingPubkey(_pubkey)) {
                return i;
            }
        }
        revert PubkeyDoesNotExit();
    }

    // only valid name with string length limit
    function onlyValidName(string calldata _name) external view {
        if (bytes(_name).length == 0) {
            revert EmptyNameString();
        }
        if (bytes(_name).length > staderConfig.getOperatorMaxNameLength()) {
            revert NameCrossedMaxLength();
        }
    }

    // checks for keys lengths, and if pubkey is already present in stader protocol
    function onlyValidKeys(
        bytes calldata _pubkey,
        bytes calldata _preDepositSignature,
        bytes calldata _depositSignature
    ) external view {
        if (_pubkey.length != PUBKEY_LENGTH) {
            revert InvalidLengthOfPubkey();
        }
        if (_preDepositSignature.length != SIGNATURE_LENGTH) {
            revert InvalidLengthOfSignature();
        }
        if (_depositSignature.length != SIGNATURE_LENGTH) {
            revert InvalidLengthOfSignature();
        }
        if (isExistingPubkey(_pubkey)) {
            revert PubkeyAlreadyExist();
        }
    }

    //compute the share of rewards between user, protocol and operator
    function calculateRewardShare(uint8 _poolId, uint256 _totalRewards)
        external
        view
        override
        returns (
            uint256 userShare,
            uint256 operatorShare,
            uint256 protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH(_poolId);
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeeBps = getProtocolFee(_poolId);
        uint256 operatorFeeBps = getOperatorFee(_poolId);

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        protocolShare = (protocolFeeBps * _userShareBeforeCommision) / staderConfig.getTotalFee();

        operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        operatorShare += (operatorFeeBps * _userShareBeforeCommision) / staderConfig.getTotalFee();

        userShare = _totalRewards - protocolShare - operatorShare;
    }

    // Modifiers
    modifier validPoolId(uint8 _poolId) {
        if (_poolId == 0 && _poolId > poolCount) {
            revert InvalidPoolID();
        }
        _;
    }
}
