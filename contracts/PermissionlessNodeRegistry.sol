// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IPermissionlessPool.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionlessNodeRegistry is
    INodeRegistry,
    IPermissionlessNodeRegistry,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint8 public constant override poolId = 1;
    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    address public override poolFactoryAddress;
    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;
    address public override permissionlessPool;
    address public override staderPenaltyFund;

    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override validatorQueueSize;
    uint256 public override nextQueuedValidatorIndex;
    uint256 public override totalActiveValidatorCount;
    uint256 public constant override PRE_DEPOSIT = 1 ether;
    uint256 public constant override FRONT_RUN_PENALTY = 3 ether;
    uint256 public constant override collateralETH = 4 ether;
    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override PERMISSIONLESS_POOL = keccak256('PERMISSIONLESS_POOL');
    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override VALIDATOR_STATUS_ROLE = keccak256('VALIDATOR_STATUS_ROLE');

    bytes32 public constant override PERMISSIONLESS_NODE_REGISTRY_OWNER =
        keccak256('PERMISSIONLESS_NODE_REGISTRY_OWNER');

    // mapping of validator Id and Validator struct
    mapping(uint256 => Validator) public override validatorRegistry;
    // mapping of validator public key and validator Id
    mapping(bytes => uint256) public override validatorIdByPubkey;
    // Queued Validator queue
    mapping(uint256 => uint256) public override queuedValidators;
    // mapping of operator Id and Operator struct
    mapping(uint256 => Operator) public override operatorStructById;
    // mapping of operator address and operator Id
    mapping(address => uint256) public override operatorIDByAddress;
    //mapping of operator wise validator IDs arrays
    mapping(uint256 => uint256[]) public override validatorIdsByOperatorId;
    mapping(uint256 => uint256) public socializingPoolStateChangeTimestamp;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _sdCollateral,
        address _staderPenaltyFund,
        address _vaultFactoryAddress,
        address _elRewardSocializePool,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_sdCollateral);
        Address.checkNonZeroAddress(_staderPenaltyFund);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        __AccessControl_init_unchained();
        __Pausable_init();
        sdCollateral = _sdCollateral;
        staderPenaltyFund = _staderPenaltyFund;
        vaultFactoryAddress = _vaultFactoryAddress;
        elRewardSocializePool = _elRewardSocializePool;
        poolFactoryAddress = _poolFactoryAddress;
        nextOperatorId = 1;
        nextValidatorId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, permissionless
     * @param _optInForMevSocialize opted in or not to socialize mev and priority fee
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address for all validator clients
     */
    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external override whenNotPaused returns (address mevFeeRecipientAddress) {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_operatorRewardAddress);

        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();

        mevFeeRecipientAddress = elRewardSocializePool;
        if (!_optInForMevSocialize) {
            mevFeeRecipientAddress = IVaultFactory(vaultFactoryAddress).deployNodeELRewardVault(
                poolId,
                nextOperatorId,
                payable(_operatorRewardAddress)
            );
        }
        _onboardOperator(_optInForMevSocialize, _operatorName, _operatorRewardAddress);
        return mevFeeRecipientAddress;
    }

    /**
     * @notice add signing keys
     * @dev only accepts if bond of 4 ETH provided along with sufficient SD lockup
     * @param _pubkey public key of validators
     * @param _preDepositSignature signature of a validators for 1ETH Deposit for checking front running
     * @param _depositSignature signature of a validators for 31ETH Deposit
     */
    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external payable override whenNotPaused {
        uint256 operatorId = _onlyActiveOperator(msg.sender);
        if (_pubkey.length != _preDepositSignature.length || _pubkey.length != _depositSignature.length)
            revert InvalidSizeOfInputKeys();

        uint256 keyCount = _pubkey.length;
        if (keyCount == 0) revert NoKeysProvided();

        if (msg.value != keyCount * collateralETH) revert InvalidBondEthValue();

        uint256 operatorTotalKeys = this.getOperatorTotalKeys(operatorId);
        uint256 operatorTotalNonWithdrawnKeys = this.getOperatorTotalNonWithdrawnKeys(msg.sender, 0, operatorTotalKeys);
        address payable operatorRewardAddress = this.getOperatorRewardAddress(operatorId);
        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughSDCollateral(msg.sender, poolId, operatorTotalNonWithdrawnKeys + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(
                _pubkey[i],
                _preDepositSignature[i],
                _depositSignature[i],
                operatorId,
                operatorRewardAddress
            );
        }
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT after receiving pre-signed
     * messages for withdrawal, handle front runned validator
     * @dev only oracle can call
     * @param _readyToDepositPubkey array of pubkeys ready to be moved to PRE_DEPOSIT state
     * @param _frontRunnedPubkey array for pubkeys which got front deposit
     * @param _invalidSignaturePubkey array of pubkey which has invalid signature for deposit
     */
    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunnedPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external override whenNotPaused onlyRole(STADER_ORACLE) {
        for (uint256 i = 0; i < _readyToDepositPubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_readyToDepositPubkey[i]];
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_readyToDepositPubkey[i], validatorId);
        }

        for (uint256 i = 0; i < _frontRunnedPubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_frontRunnedPubkey[i]];
            _handleFrontRun(validatorId);
            emit ValidatorMarkedAsFrontRunned(_frontRunnedPubkey[i], validatorId);
        }

        for (uint256 i = 0; i < _invalidSignaturePubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_invalidSignaturePubkey[i]];
            validatorRegistry[validatorId].status = ValidatorStatus.INVALID_SIGNATURE;
            emit ValidatorStatusMarkedAsInvalidSignature(_invalidSignaturePubkey[i], validatorId);
        }
    }

    /**
     * @notice update the next queued validator index by a count
     * @dev accept call from permissionless pool
     * @param _nextQueuedValidatorIndex updated next index of queued validator
     */
    function updateNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex) external onlyRole(PERMISSIONLESS_POOL) {
        nextQueuedValidatorIndex = _nextQueuedValidatorIndex;
        emit UpdatedNextQueuedValidatorIndex(nextQueuedValidatorIndex);
    }

    function changeSocializingPoolState(bool _optedForSocializingPool) external {
        _onlyActiveOperator(msg.sender);
        uint256 operatorId = operatorIDByAddress[msg.sender];
        require(
            operatorStructById[operatorId].optedForSocializingPool != _optedForSocializingPool,
            'No change in state'
        );

        operatorStructById[operatorId].optedForSocializingPool = _optedForSocializingPool;
        socializingPoolStateChangeTimestamp[operatorId] = block.timestamp;
        emit UpdatedSocializingPoolState(operatorId, _optedForSocializingPool, block.timestamp);
    }

    /// @inheritdoc INodeRegistry
    function getSocializingPoolStateChangeTimestamp(uint256 _operatorId) external view returns (uint256) {
        return socializingPoolStateChangeTimestamp[_operatorId];
    }

    /// @inheritdoc INodeRegistry
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        if (validatorId == 0) {
            Operator memory emptyOperator;

            return emptyOperator;
        }

        uint256 operatorId = validatorRegistry[validatorId].operatorId;
        return operatorStructById[operatorId];
    }

    /**
     * @notice update the status of a validator
     * @dev only oracle can call
     * @param _pubkey public key of the validator
     * @param _status updated status of validator
     */
    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status)
        external
        override
        onlyRole(VALIDATOR_STATUS_ROLE)
    {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        validatorRegistry[validatorId].status = _status;
    }

    /**
     * @notice updates the address of pool factory
     * @dev only admin can call
     * @param _poolFactoryAddress address of pool factory
     */
    function updatePoolFactoryAddress(address _poolFactoryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_poolFactoryAddress);
        poolFactoryAddress = _poolFactoryAddress;
        emit UpdatedPoolFactoryAddress(poolFactoryAddress);
    }

    /**
     * @notice update the address of sd collateral contract
     * @dev only admin can call
     * @param _sdCollateral address of sd collateral contract
     */
    function updateSDCollateralAddress(address _sdCollateral)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_sdCollateral);
        sdCollateral = _sdCollateral;
        emit UpdatedSDCollateralAddress(_sdCollateral);
    }

    /**
     * @notice update the address of vault factory
     * @dev only admin can call
     * @param _vaultFactoryAddress address of vault factory
     */
    function updateVaultFactoryAddress(address _vaultFactoryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        vaultFactoryAddress = _vaultFactoryAddress;
        emit UpdatedVaultFactoryAddress(_vaultFactoryAddress);
    }

    /**
     * @notice add the permission less pool address in permission less node registry
     * for the purpose of doing 1ETH PRE DEPOSIT
     * @dev only admin can update
     * @param _permissionlessPool permission less pool address
     */
    function updatePermissionlessPoolAddress(address _permissionlessPool)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_permissionlessPool);
        permissionlessPool = _permissionlessPool;
        emit UpdatedPermissionlessPoolAddress(permissionlessPool);
    }

    /**
     * @notice update the address of permissionless socialize pool
     * @dev only admin can call
     * @param _elRewardSocializePool address of permissionless EL reward socialize pool
     */
    function updateELRewardSocializePool(address _elRewardSocializePool)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_elRewardSocializePool);
        elRewardSocializePool = _elRewardSocializePool;
        emit UpdatedELRewardSocializePool(_elRewardSocializePool);
    }

    /**
     * @notice update the address of stader penalty fund
     * @dev only admin can call
     * @param _staderPenaltyFund address of stader penalty fund
     */
    function updateStaderPenaltyFundAddress(address _staderPenaltyFund)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_staderPenaltyFund);
        staderPenaltyFund = _staderPenaltyFund;
        emit UpdatedStaderPenaltyFund(_staderPenaltyFund);
    }

    /**
     * @notice update the name and reward address of an operator
     * @dev only operator msg.sender can update
     * @param _operatorName new Name of the operator
     * @param _rewardAddress new reward address
     */
    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external override {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_rewardAddress);

        _onlyActiveOperator(msg.sender);
        uint256 operatorId = operatorIDByAddress[msg.sender];
        operatorStructById[operatorId].operatorName = _operatorName;
        operatorStructById[operatorId].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorDetails(msg.sender, _operatorName, _rewardAddress);
    }

    /**
     * @notice increase the total active validator count
     * @dev only permissionless pool calls it when it does the deposit of 31ETH for validator
     * @param _count count to increase total active validator value
     */
    function increaseTotalActiveValidatorCount(uint256 _count) external override onlyRole(PERMISSIONLESS_POOL) {
        totalActiveValidatorCount += _count;
    }

    /**
     * @notice decrease the total active validator count
     * @dev only stader oracle calls it when it report withdrawn validators
     * @param _count count to decrease total active validator value
     */
    function decreaseTotalActiveValidatorCount(uint256 _count) external override onlyRole(STADER_ORACLE) {
        totalActiveValidatorCount -= _count;
    }

    /**
     * @notice transfer the `_amount` to permissionless pool
     * @dev only permissionless pool can call
     * @param _amount amount of eth to send to permissionless pool
     */
    function transferCollateralToPool(uint256 _amount) external override whenNotPaused onlyRole(PERMISSIONLESS_POOL) {
        (, address poolAddress) = IPoolFactory(poolFactoryAddress).pools(poolId);
        _sendValue(poolAddress, _amount);
    }

    /**
     * @notice get the total non withdrawn keys for an operator
     * @dev loop over all keys of an operator from start index till
     *  end index (exclusive) to get the count excluding the withdrawn keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalNonWithdrawnKeys(
        address _nodeOperator,
        uint256 startIndex,
        uint256 endIndex
    ) external view override returns (uint256) {
        if (startIndex > endIndex) {
            revert InvalidStartAndEndIndex();
        }
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        uint256 validatorCount = this.getOperatorTotalKeys(operatorId);
        endIndex = endIndex > validatorCount ? validatorCount : endIndex;
        uint256 totalNonWithdrawnKeyCount;
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 validatorId = validatorIdsByOperatorId[operatorId][i];
            if (_isWithdrawnValidator(validatorId)) continue;
            totalNonWithdrawnKeyCount++;
        }
        return totalNonWithdrawnKeyCount;
    }

    /**
     * @notice get the total added keys for an operator
     * @dev length of the validatorIds array for an operator
     * @param _operatorId ID of node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) external view override returns (uint256 _totalKeys) {
        _totalKeys = validatorIdsByOperatorId[_operatorId].length;
    }

    /**
     * @notice return total queued keys for permissionless pool
     * @return _validatorCount total queued validator count
     */
    function getTotalQueuedValidatorCount() public view override returns (uint256) {
        return validatorQueueSize - nextQueuedValidatorIndex;
    }

    /**
     * @notice return total active keys for permissionless pool
     * @return _validatorCount total active validator count
     */
    function getTotalActiveValidatorCount() public view override returns (uint256) {
        return totalActiveValidatorCount;
    }

    function getCollateralETH() external pure override returns (uint256) {
        return collateralETH;
    }

    /**
     * @notice returns the operator reward address
     * @param _operatorId operator ID
     */
    function getOperatorRewardAddress(uint256 _operatorId) external view override returns (address payable) {
        return operatorStructById[_operatorId].operatorRewardAddress;
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external override onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external override onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER) {
        _unpause();
    }

    /**
     * @notice returns the validator for which protocol don't have money on execution layer
     * @dev loop over all validator to filter out the initialized, front run and withdrawn and return the rest
     */
    function getAllActiveValidators() public view override returns (Validator[] memory) {
        Validator[] memory validators = new Validator[](this.getTotalActiveValidatorCount());
        uint256 validatorCount = 0;
        for (uint256 i = 1; i < nextValidatorId; i++) {
            if (_isActiveValidator(i)) {
                validators[validatorCount] = validatorRegistry[i];
                validatorCount++;
            }
        }
        return validators;
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return validatorRegistry[validatorIdByPubkey[_pubkey]];
    }

    function getValidator(uint256 _validatorId) external view returns (Validator memory) {
        return validatorRegistry[_validatorId];
    }

    function _onboardOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) internal {
        operatorStructById[nextOperatorId] = Operator(
            true,
            _optInForMevSocialize,
            _operatorName,
            _operatorRewardAddress,
            msg.sender
        );
        operatorIDByAddress[msg.sender] = nextOperatorId;
        socializingPoolStateChangeTimestamp[nextOperatorId] = block.timestamp;
        nextOperatorId++;

        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    function _addValidatorKey(
        bytes calldata _pubkey,
        bytes calldata _preDepositSignature,
        bytes calldata _depositSignature,
        uint256 _operatorId,
        address payable _operatorRewardAddress
    ) internal {
        uint256 totalKeys = this.getOperatorTotalKeys(_operatorId);
        _validateKeys(_pubkey, _preDepositSignature, _depositSignature);
        address withdrawVault = IVaultFactory(vaultFactoryAddress).deployWithdrawVault(
            poolId,
            _operatorId,
            totalKeys,
            _operatorRewardAddress
        );

        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            _pubkey,
            _preDepositSignature,
            _depositSignature,
            withdrawVault,
            _operatorId,
            collateralETH
        );

        //slither-disable-next-line arbitrary-send-eth
        IPermissionlessPool(permissionlessPool).preDepositOnBeacon{value: PRE_DEPOSIT}(
            _pubkey,
            _preDepositSignature,
            withdrawVault
        );
        validatorIdByPubkey[_pubkey] = nextValidatorId;
        validatorIdsByOperatorId[_operatorId].push(nextValidatorId);
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubkey, nextValidatorId - 1);
    }

    // mark validator ready to deposit after successful key verification and front run check
    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queuedValidators[validatorQueueSize] = _validatorId;
        validatorQueueSize++;
    }

    // handle front run validator by changing their status, deactivating operator and imposing penalty
    function _handleFrontRun(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.FRONT_RUN;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorStructById[operatorId].active = false;
        _sendValue(staderPenaltyFund, FRONT_RUN_PENALTY);
    }

    // checks for keys lengths, and if pubkey is already there
    function _validateKeys(
        bytes calldata pubkey,
        bytes calldata preDepositSignature,
        bytes calldata depositSignature
    ) private view {
        if (pubkey.length != PUBKEY_LENGTH) revert InvalidLengthOfpubkey();
        if (preDepositSignature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (depositSignature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (validatorIdByPubkey[pubkey] != 0) revert pubkeyAlreadyExist();
    }

    function _sendValue(address receiver, uint256 _amount) internal {
        if (address(this).balance < _amount) revert InSufficientBalance();

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(receiver).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }

    // operator in active state
    function _onlyActiveOperator(address operAddr) internal view returns (uint256 _operatorId) {
        _operatorId = operatorIDByAddress[operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        if (!operatorStructById[_operatorId].active) revert OperatorIsDeactivate();
    }

    // only valid name with string length limit
    function _onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }

    // checks if validator is withdrawn
    function _isWithdrawnValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        if (validator.status == ValidatorStatus.WITHDRAWN) return true;
        return false;
    }

    // checks if validator is active, active validator are those having user share on beacon chain
    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        if (
            validator.status == ValidatorStatus.INITIALIZED ||
            validator.status == ValidatorStatus.INVALID_SIGNATURE ||
            validator.status == ValidatorStatus.FRONT_RUN ||
            validator.status == ValidatorStatus.PRE_DEPOSIT ||
            validator.status == ValidatorStatus.WITHDRAWN
        ) return false;
        return true;
    }
}
