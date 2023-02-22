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
    uint64 private constant pubkey_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    address public poolFactoryAddress;
    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;
    address public override permissionlessPool;
    address public override staderInsuranceFund;

    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override validatorQueueSize;
    uint256 public override nextQueuedValidatorIndex;
    uint256 public override totalInitializedValidatorCount;
    uint256 public override totalQueuedValidatorCount;
    uint256 public override totalActiveValidatorCount;
    uint256 public override totalWithdrawnValidatorCount;
    uint256 public constant override PRE_DEPOSIT = 1 ether;
    uint256 public constant override FRONT_RUN_PENALTY = 3 ether;
    uint256 public constant override collateralETH = 4 ether;

    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override PERMISSIONLESS_POOL = keccak256('PERMISSIONLESS_POOL');
    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override VALIDATOR_STATUS_ROLE = keccak256('VALIDATOR_STATUS_ROLE');
    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');

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
    // timestamp when operator opted for socializing pool
    mapping(uint256 => uint256) public override socializingPoolStateChangeTimestamp;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _staderInsuranceFund,
        address _vaultFactoryAddress,
        address _elRewardSocializePool,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_staderInsuranceFund);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        __AccessControl_init_unchained();
        __Pausable_init();
        staderInsuranceFund = _staderInsuranceFund;
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
     * @param _validatorpubkey public key of validators
     * @param _validatorSignature signature of a validators
     */
    function addValidatorKeys(bytes[] calldata _validatorpubkey, bytes[] calldata _validatorSignature)
        external
        payable
        override
        whenNotPaused
    {
        uint256 operatorId = _onlyOnboardedOperator(msg.sender);
        if (_validatorpubkey.length != _validatorSignature.length) revert InvalidSizeOfInputKeys();

        uint256 keyCount = _validatorpubkey.length;
        if (keyCount == 0) revert NoKeysProvided();

        if (msg.value != keyCount * collateralETH) revert InvalidBondEthValue();

        Operator storage operator = operatorStructById[operatorId];

        uint256 totalNonWithdrawnKeys = this.getOperatorTotalKeys(msg.sender) - operator.withdrawnValidatorCount;

        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughXSDCollateral(msg.sender, poolId, totalNonWithdrawnKeys + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_validatorpubkey[i], _validatorSignature[i], operatorId);
        }
        totalInitializedValidatorCount += keyCount;
        _increaseInitializedValidatorCount(operator, keyCount);
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT after receiving pre-signed messages for withdrawal
     * @dev only admin can call
     * @param _pubkeys array of pubkeys ready to be moved to PRE_DEPOSIT state
     */
    function markValidatorReadyToDeposit(bytes[] calldata _pubkeys)
        external
        override
        whenNotPaused
        onlyRole(STADER_MANAGER_BOT)
    {
        uint256 inputSize = _pubkeys.length;
        for (uint256 i = 0; i < inputSize; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            if (validatorId == 0) revert pubkeyDoesNotExist();
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubkeys[i], validatorId);
        }
        totalInitializedValidatorCount -= inputSize;
        totalQueuedValidatorCount += inputSize;
    }

    /**
     * @notice reports the front running validator
     * @dev only stader DAO can call
     * @param _validatorIds array of validator IDs which got front running deposit
     */
    function reportFrontRunValidators(uint256[] calldata _validatorIds) external onlyRole(STADER_ORACLE) {
        uint256 inputSize = _validatorIds.length;
        for (uint256 i = 0; i < inputSize; i++) {
            _handleFrontRun(_validatorIds[i]);
        }
        totalInitializedValidatorCount -= inputSize;
        totalWithdrawnValidatorCount += inputSize;
    }

    /**
     * @notice reduce the queued validator count and increase active validator count for a operator
     * @dev only accept call from permissionless pool contract
     * @param _operatorId operator ID
     */
    function updateQueuedAndActiveValidatorsCount(uint256 _operatorId) external override onlyRole(PERMISSIONLESS_POOL) {
        _updateQueuedAndActiveValidatorsCount(_operatorId);
    }

    /**
     * @notice reduce the active validator count and increase withdrawn validator count for a operator
     * @dev only accept call from accounts having `STADER_ORACLE` role
     * @param _operatorId operator ID
     */
    function updateActiveAndWithdrawnValidatorsCount(uint256 _operatorId) external override onlyRole(STADER_ORACLE) {
        _updateActiveAndWithdrawnValidatorsCount(_operatorId);
    }

    /**
     * @notice update the next queued validator index by a count
     * @dev accept call from permissionless pool
     * @param _count count of validators picked from queue, nextIndex after `_count`
     */
    function updateNextQueuedValidatorIndex(uint256 _count) external onlyRole(PERMISSIONLESS_POOL) {
        nextQueuedValidatorIndex += _count;
        emit UpdatedNextQueuedValidatorIndex(nextQueuedValidatorIndex);
    }

    function changeSocializingPoolState(bool _optedForSocializingPool) external {
        _onlyOnboardedOperator(msg.sender);
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
     * @notice get the total deposited keys for an operator
     * @dev add initialized, queued, active and withdrawn validator key count to get total validators keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalNonWithdrawnKeys(address _nodeOperator)
        external
        view
        override
        returns (uint256 _totalKeys)
    {
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        Operator memory operator = operatorStructById[operatorId];
        _totalKeys = operator.initializedValidatorCount + operator.queuedValidatorCount + operator.activeValidatorCount;
    }

    /**
     * @notice get the total non withdrawn keys for an operator
     * @dev add initialized, queued and active validator key count to get total validators keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalKeys(address _nodeOperator) external view override returns (uint256 _totalKeys) {
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        _totalKeys =
            operatorStructById[operatorId].initializedValidatorCount +
            operatorStructById[operatorId].queuedValidatorCount +
            operatorStructById[operatorId].activeValidatorCount +
            operatorStructById[operatorId].withdrawnValidatorCount;
    }

    /**
     * @notice transfer the `_amount` to permissionless pool
     * @dev only permissionless pool can call
     * @param _amount amount of eth to send to permissionless pool
     */
    //TODO decide on the role name
    function transferCollateralToPool(uint256 _amount) external override whenNotPaused onlyRole(PERMISSIONLESS_POOL) {
        (, address poolAddress) = IPoolFactory(poolFactoryAddress).pools(poolId);
        _sendValue(poolAddress, _amount);
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
        if (validatorId == 0) revert pubkeyDoesNotExist();
        validatorRegistry[validatorId].status = _status;
    }

    /**
     * @notice updates the address of pool factory
     * @dev only NOs registry can call
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
     * @notice update the name and reward address of an operator
     * @dev only operator msg.sender can update
     * @param _operatorName new Name of the operator
     * @param _rewardAddress new reward address
     */
    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external override {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_rewardAddress);

        _onlyOnboardedOperator(msg.sender);
        uint256 operatorId = operatorIDByAddress[msg.sender];
        operatorStructById[operatorId].operatorName = _operatorName;
        operatorStructById[operatorId].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorDetails(msg.sender, _operatorName, _rewardAddress);
    }

    /**
     * @notice return total queued keys for permissionless pool
     * @return _validatorCount total queued validator count
     */
    function getTotalQueuedValidatorCount() public view override returns (uint256) {
        return totalQueuedValidatorCount;
    }

    /**
     * @notice return total active keys for permissionless pool
     * @return _validatorCount total active validator count
     */
    function getTotalActiveValidatorCount() public view override returns (uint256) {
        return totalActiveValidatorCount;
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
            msg.sender,
            0,
            0,
            0,
            0
        );
        operatorIDByAddress[msg.sender] = nextOperatorId;
        nextOperatorId++;
        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    function _addValidatorKey(
        bytes calldata _pubkey,
        bytes calldata _signature,
        uint256 _operatorId
    ) internal {
        uint256 totalKeys = this.getOperatorTotalKeys(msg.sender);
        _validateKeys(_pubkey, _signature);
        address withdrawVault = IVaultFactory(vaultFactoryAddress).deployWithdrawVault(poolId, _operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            false,
            _pubkey,
            _signature,
            withdrawVault,
            _operatorId,
            collateralETH
        );

        //slither-disable-next-line arbitrary-send-eth
        IPermissionlessPool(permissionlessPool).preDepositOnBeacon{value: PRE_DEPOSIT}(
            _pubkey,
            _signature,
            withdrawVault
        );
        validatorIdByPubkey[_pubkey] = nextValidatorId;
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubkey, nextValidatorId - 1);
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queuedValidators[validatorQueueSize] = _validatorId;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        _updateInitializedAndQueuedValidatorCount(operatorId);
        validatorQueueSize++;
    }

    function _handleFrontRun(uint256 _validatorId) internal {
        Validator storage validator = validatorRegistry[_validatorId];
        validator.isFrontRun = true;
        _updateInitializedAndWithdrawnValidatorCount(validator.operatorId);
        _sendValue(staderInsuranceFund, FRONT_RUN_PENALTY);
    }

    function _validateKeys(bytes calldata pubkey, bytes calldata signature) private view {
        if (pubkey.length != pubkey_LENGTH) revert InvalidLengthOfpubkey();
        if (signature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (validatorIdByPubkey[pubkey] != 0) revert pubkeyAlreadyExist();
    }

    function _sendValue(address receiver, uint256 _amount) internal {
        if (address(this).balance < _amount) revert InSufficientBalance();

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(receiver).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }

    function _onlyOnboardedOperator(address operAddr) internal view returns (uint256 _operatorId) {
        _operatorId = operatorIDByAddress[operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
    }

    function _onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }

    function _increaseInitializedValidatorCount(Operator storage _operator, uint256 _count) internal {
        _operator.initializedValidatorCount += _count;
    }

    function _updateInitializedAndQueuedValidatorCount(uint256 _operatorId) internal {
        Operator storage operator = operatorStructById[_operatorId];
        operator.initializedValidatorCount--;
        operator.queuedValidatorCount++;
    }

    function _updateQueuedAndActiveValidatorsCount(uint256 _operatorId) internal {
        Operator storage operator = operatorStructById[_operatorId];
        operator.queuedValidatorCount--;
        operator.activeValidatorCount++;
        totalQueuedValidatorCount--;
        totalActiveValidatorCount++;
        emit UpdatedQueuedAndActiveValidatorsCount(
            _operatorId,
            operator.queuedValidatorCount,
            operator.activeValidatorCount
        );
    }

    function _updateActiveAndWithdrawnValidatorsCount(uint256 _operatorId) internal {
        Operator storage operator = operatorStructById[_operatorId];
        operator.activeValidatorCount--;
        operator.withdrawnValidatorCount++;
        totalActiveValidatorCount--;
        totalWithdrawnValidatorCount++;
        emit UpdatedActiveAndWithdrawnValidatorsCount(
            _operatorId,
            operator.activeValidatorCount,
            operator.withdrawnValidatorCount
        );
    }

    function _updateInitializedAndWithdrawnValidatorCount(uint256 _operatorId) internal {
        Operator storage operator = operatorStructById[_operatorId];
        operator.initializedValidatorCount--;
        operator.withdrawnValidatorCount++;
    }

    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        if (
            validator.status == ValidatorStatus.INITIALIZED ||
            validator.status == ValidatorStatus.PRE_DEPOSIT ||
            validator.status == ValidatorStatus.WITHDRAWN
        ) return false;
        return true;
    }
}
