// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './library/ValidatorStatus.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IPermissionlessPool.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IValidatorWithdrawalVault.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract PermissionlessNodeRegistry is
    INodeRegistry,
    IPermissionlessNodeRegistry,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint8 public constant override poolId = 1;
    uint16 public override inputKeyCountLimit;
    uint64 public override maxNonTerminalKeyPerOperator;
    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    IStaderConfig public staderConfig;

    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override validatorQueueSize;
    uint256 public override nextQueuedValidatorIndex;
    uint256 public override totalActiveValidatorCount;
    uint256 public constant override PRE_DEPOSIT = 1 ether;
    uint256 public constant override FRONT_RUN_PENALTY = 3 ether;
    uint256 public constant override collateralETH = 4 ether;

    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override PERMISSIONLESS_POOL = keccak256('PERMISSIONLESS_POOL');
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
    mapping(uint256 => uint256) public socializingPoolStateChangeBlock;
    //mapping of nodeELReward vault address with operator address
    mapping(address => address) public override nodeELRewardVaultByOperator;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(address _staderConfig) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        nextOperatorId = 1;
        nextValidatorId = 1;
        inputKeyCountLimit = 100;
        maxNonTerminalKeyPerOperator = 50;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, permissionless
     * @param _optInForSocializingPool opted in or not to socialize mev and priority fee
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return feeRecipientAddress fee recipient address for all validator clients
     */
    function onboardNodeOperator(
        bool _optInForSocializingPool,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external override whenNotPaused returns (address feeRecipientAddress) {
        _onlyValidName(_operatorName);
        AddressLib.checkNonZeroAddress(_operatorRewardAddress);
        //TODO sanjay check for operator, should not be in other pool
        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();

        //deploy NodeELRewardVault for NO
        address nodeELRewardVault = IVaultFactory(staderConfig.getVaultFactory()).deployNodeELRewardVault(
            poolId,
            nextOperatorId,
            payable(_operatorRewardAddress)
        );
        nodeELRewardVaultByOperator[msg.sender] = nodeELRewardVault;
        feeRecipientAddress = _optInForSocializingPool
            ? staderConfig.getPermissionlessSocializingPool()
            : nodeELRewardVault;
        _onboardOperator(_optInForSocializingPool, _operatorName, _operatorRewardAddress);
        //TODO sanjay, function signature only in interface, ask Manoj for full function
        ISDCollateral(staderConfig.getSDCollateral()).updatePoolIdForOperator(poolId, msg.sender);
        return feeRecipientAddress;
    }

    /**
     * @notice add signing keys
     * @dev only accepts if bond of 4 ETH per key is provided along with sufficient SD lockup
     * @param _pubkey public key of validators
     * @param _preDepositSignature signature of a validators for 1ETH deposit
     * @param _depositSignature signature of a validator for 31ETH deposit
     */
    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external payable override nonReentrant whenNotPaused {
        uint256 operatorId = _onlyActiveOperator(msg.sender);
        (uint256 keyCount, uint256 operatorTotalKeys) = _checkInputKeysCountAndCollateral(
            poolId,
            _pubkey.length,
            _preDepositSignature.length,
            _depositSignature.length,
            operatorId
        );
        address payable operatorRewardAddress = getOperatorRewardAddress(operatorId);
        address vaultFactory = staderConfig.getVaultFactory();
        address poolFactory = staderConfig.getPoolFactory();
        for (uint256 i = 0; i < keyCount; i++) {
            _validateKeys(_pubkey[i], _preDepositSignature[i], _depositSignature[i], poolFactory);
            address withdrawVault = IVaultFactory(vaultFactory).deployWithdrawVault(
                poolId,
                operatorId,
                operatorTotalKeys + i, //operator totalKeys
                nextValidatorId,
                operatorRewardAddress
            );
            validatorRegistry[nextValidatorId] = Validator(
                ValidatorStatus.INITIALIZED,
                _pubkey[i],
                _preDepositSignature[i],
                _depositSignature[i],
                withdrawVault,
                operatorId,
                collateralETH,
                0,
                0
            );

            validatorIdByPubkey[_pubkey[i]] = nextValidatorId;
            validatorIdsByOperatorId[operatorId].push(nextValidatorId);
            emit AddedValidatorKey(msg.sender, _pubkey[i], nextValidatorId);
            nextValidatorId++;
        }

        //TODO sanjay why are we not marking PRE_DEPOSIT status after 1ETH deposit
        //slither-disable-next-line arbitrary-send-eth
        IPermissionlessPool(staderConfig.getPermissionlessPool()).preDepositOnBeaconChain{
            value: PRE_DEPOSIT * keyCount
        }(_pubkey, _preDepositSignature, operatorId, operatorTotalKeys);
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT
     * after verifying pre-sign message, front running and deposit signature.
     * report front run and invalid signature pubkeys
     * @dev only oracle can call
     * @param _readyToDepositPubkey array of pubkeys ready to be moved to PRE_DEPOSIT state
     * @param _frontRunnedPubkey array for pubkeys which got front deposit
     * @param _invalidSignaturePubkey array of pubkey which has invalid signature for deposit
     */
    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunnedPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external override whenNotPaused nonReentrant onlyRole(STADER_ORACLE) {
        for (uint256 i = 0; i < _readyToDepositPubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_readyToDepositPubkey[i]];
            _onlyInitializedValidator(validatorId);
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_readyToDepositPubkey[i], validatorId);
        }

        address staderPenaltyFund = staderConfig.getStaderPenaltyFund();
        for (uint256 i = 0; i < _frontRunnedPubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_frontRunnedPubkey[i]];
            _onlyInitializedValidator(validatorId);
            _handleFrontRun(staderPenaltyFund, validatorId);
            emit ValidatorMarkedAsFrontRunned(_frontRunnedPubkey[i], validatorId);
        }

        for (uint256 i = 0; i < _invalidSignaturePubkey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_invalidSignaturePubkey[i]];
            _onlyInitializedValidator(validatorId);
            _handleInvalidSignature(validatorId);
            emit ValidatorStatusMarkedAsInvalidSignature(_invalidSignaturePubkey[i], validatorId);
        }
        _decreaseTotalActiveValidatorCount(_frontRunnedPubkey.length + _invalidSignaturePubkey.length);
    }

    /**
     * @notice handling of fully withdrawn validators
     * @dev list of pubkeys reported by oracle, settle all EL and CL vault balances
     * @param  _pubkeys array of withdrawn validator's pubkey
     */
    function withdrawnValidators(bytes[] calldata _pubkeys) external onlyRole(STADER_ORACLE) {
        uint256 withdrawnValidatorCount = _pubkeys.length;
        for (uint256 i = 0; i < withdrawnValidatorCount; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            if (!_isNonTerminalValidator(validatorId)) revert UNEXPECTED_STATUS();
            Validator storage validator = validatorRegistry[validatorId];
            validator.status = ValidatorStatus.WITHDRAWN;
            validator.withdrawnBlock = block.number;
            IValidatorWithdrawalVault(validator.withdrawVaultAddress).settleFunds();
            uint256 operatorId = validator.operatorId;
            if (!operatorStructById[operatorId].optedForSocializingPool) {
                address nodeELRewardVault = IVaultFactory(staderConfig.getVaultFactory())
                    .computeNodeELRewardVaultAddress(poolId, operatorId);
                INodeELRewardVault(nodeELRewardVault).withdraw();
            }
            emit ValidatorWithdrawn(_pubkeys[i], validatorId);
        }
        _decreaseTotalActiveValidatorCount(withdrawnValidatorCount);
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

    /**
     * @notice sets the depositTime for a validator
     * @dev only permissionless pool can call
     * @param _validatorId ID of the validator
     */
    function updateDepositStatusAndBlock(uint256 _validatorId) external override onlyRole(PERMISSIONLESS_POOL) {
        validatorRegistry[_validatorId].depositBlock = block.number;
        _markValidatorDeposited(_validatorId);
        emit UpdatedValidatorDepositBlock(_validatorId, block.number);
    }

    // allow NOs to opt in/out of socialize pool after coolDownPeriod i.e `getSocializingPoolCoolingPeriod`
    function changeSocializingPoolState(bool _optInForSocializingPool)
        external
        override
        returns (address feeRecipientAddress)
    {
        uint256 operatorId = _onlyActiveOperator(msg.sender);
        //TODO sanjay configure formatter to put braces in single if/else statements
        if (operatorStructById[operatorId].optedForSocializingPool == _optInForSocializingPool)
            revert NoChangeInState();

        if (
            block.number <
            socializingPoolStateChangeBlock[operatorId] + 2 * staderConfig.getSocializingPoolCoolingPeriod()
        ) revert CooldownNotComplete();
        feeRecipientAddress = IVaultFactory(staderConfig.getVaultFactory()).computeNodeELRewardVaultAddress(
            poolId,
            operatorId
        );
        if (_optInForSocializingPool) {
            INodeELRewardVault(feeRecipientAddress).withdraw();
            feeRecipientAddress = staderConfig.getPermissionlessSocializingPool();
        }
        operatorStructById[operatorId].optedForSocializingPool = _optInForSocializingPool;
        socializingPoolStateChangeBlock[operatorId] = block.number;
        emit UpdatedSocializingPoolState(operatorId, _optInForSocializingPool, block.number);
    }

    // @inheritdoc INodeRegistry
    function getSocializingPoolStateChangeBlock(uint256 _operatorId) external view returns (uint256) {
        return socializingPoolStateChangeBlock[_operatorId];
    }

    // @inheritdoc INodeRegistry
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
     * @notice update maximum key to be deposited in a batch
     * @dev only admin can call
     * @param _inputKeyCountLimit updated maximum key limit in the input
     */
    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        inputKeyCountLimit = _inputKeyCountLimit;
        emit UpdatedInputKeyCountLimit(inputKeyCountLimit);
    }

    /**
     * @notice update the maximum non terminal key limit per operator
     * @dev only admin can call
     * @param _maxNonTerminalKeyPerOperator updated maximum non terminal key per operator limit
     */
    function updateMaxNonTerminalKeyPerOperator(uint64 _maxNonTerminalKeyPerOperator)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        maxNonTerminalKeyPerOperator = _maxNonTerminalKeyPerOperator;
        emit UpdatedMaxNonTerminalKeyPerOperator(maxNonTerminalKeyPerOperator);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice update the name and reward address of an operator
     * @dev only operator msg.sender can update
     * @param _operatorName new name of the operator
     * @param _rewardAddress new reward address
     */
    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external override {
        _onlyValidName(_operatorName);
        AddressLib.checkNonZeroAddress(_rewardAddress);
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
        emit IncreasedTotalActiveValidatorCount(totalActiveValidatorCount);
    }

    /**
     * @notice transfer the `_amount` to permissionless pool
     * @dev only permissionless pool can call
     * @param _amount amount of eth to send to permissionless pool
     */
    function transferCollateralToPool(uint256 _amount) external override whenNotPaused onlyRole(PERMISSIONLESS_POOL) {
        IPermissionlessPool(staderConfig.getPermissionlessPool()).receiveRemainingCollateralETH{value: _amount}();
        emit TransferredCollateralToPool(_amount);
    }

    /**
     * @param _nodeOperator @notice operator total non withdrawn keys within a specified validator list
     * @param _startIndex start index in validator queue to start with
     * @param _endIndex  up to end index of validator queue to to count
     */
    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) public view override returns (uint64) {
        if (_startIndex > _endIndex) {
            revert InvalidStartAndEndIndex();
        }
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        uint256 validatorCount = getOperatorTotalKeys(operatorId);
        _endIndex = _endIndex > validatorCount ? validatorCount : _endIndex;
        uint64 totalNonWithdrawnKeyCount;
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            uint256 validatorId = validatorIdsByOperatorId[operatorId][i];
            if (_isNonTerminalValidator(validatorId)) {
                totalNonWithdrawnKeyCount++;
            }
        }
        return totalNonWithdrawnKeyCount;
    }

    /**
     * @notice get the total added keys for an operator
     * @dev length of the validatorIds array for an operator
     * @param _operatorId ID of node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) public view override returns (uint256 _totalKeys) {
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
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return totalActiveValidatorCount;
    }

    function getCollateralETH() external pure override returns (uint256) {
        return collateralETH;
    }

    /**
     * @notice returns the operator reward address
     * @param _operatorId operator ID
     */
    function getOperatorRewardAddress(uint256 _operatorId) public view override returns (address payable) {
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
     * @notice Returns an array of active validators
     *
     * @param _pageNumber The page number of the results to fetch (starting from 1).
     * @param _pageSize The maximum number of items per page.
     *
     * @return An array of `Validator` objects representing the active validators.
     */
    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize)
        public
        view
        override
        returns (Validator[] memory)
    {
        if (_pageNumber == 0) revert PageNumberIsZero();
        uint256 startIndex = (_pageNumber - 1) * _pageSize + 1;
        uint256 endIndex = startIndex + _pageSize;
        endIndex = endIndex > nextValidatorId ? nextValidatorId : endIndex;
        Validator[] memory validators = new Validator[](_pageSize);
        uint256 validatorCount = 0;
        for (uint256 i = startIndex; i < endIndex; i++) {
            if (_isActiveValidator(i)) {
                validators[validatorCount] = validatorRegistry[i];
                validatorCount++;
            }
        }
        // If the result array isn't full, resize it to remove the unused elements
        assembly {
            mstore(validators, validatorCount)
        }

        return validators;
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return validatorRegistry[validatorIdByPubkey[_pubkey]];
    }

    function getValidator(uint256 _validatorId) external view returns (Validator memory) {
        return validatorRegistry[_validatorId];
    }

    // check for duplicate keys in permissionless node registry
    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return validatorIdByPubkey[_pubkey] != 0;
    }

    function _onboardOperator(
        bool _optInForSocializingPool,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) internal {
        operatorStructById[nextOperatorId] = Operator(
            true,
            _optInForSocializingPool,
            _operatorName,
            _operatorRewardAddress,
            msg.sender
        );
        operatorIDByAddress[msg.sender] = nextOperatorId;
        socializingPoolStateChangeBlock[nextOperatorId] = block.number;
        nextOperatorId++;

        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    // mark validator ready to deposit after successful key verification and front run check
    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queuedValidators[validatorQueueSize] = _validatorId;
        validatorQueueSize++;
    }

    // handle front run validator by changing their status, deactivating operator and imposing penalty
    function _handleFrontRun(address _staderPenaltyFund, uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.FRONT_RUN;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorStructById[operatorId].active = false;
        _sendValue(_staderPenaltyFund, FRONT_RUN_PENALTY);
    }

    // handle validator with invalid signature for 1ETH deposit
    function _handleInvalidSignature(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.INVALID_SIGNATURE;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        address operatorAddress = operatorStructById[operatorId].operatorAddress;
        _sendValue(operatorAddress, collateralETH - PRE_DEPOSIT);
    }

    // checks for keys lengths, and if pubkey is already present in stader protocol(not just permissionless pool)
    function _validateKeys(
        bytes calldata _pubkey,
        bytes calldata _preDepositSignature,
        bytes calldata _depositSignature,
        address _poolFactory
    ) private view {
        if (_pubkey.length != PUBKEY_LENGTH) revert InvalidLengthOfPubkey();
        if (_preDepositSignature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (_depositSignature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (IPoolFactory(_poolFactory).isExistingPubkey(_pubkey)) revert PubkeyAlreadyExist();
    }

    // validate the input of `addValidatorKeys` function
    function _checkInputKeysCountAndCollateral(
        uint8 _poolId,
        uint256 _pubkeyLength,
        uint256 _preDepositSignatureLength,
        uint256 _depositSignatureLength,
        uint256 _operatorId
    ) internal view returns (uint256 keyCount, uint256 totalKeys) {
        if (_pubkeyLength != _preDepositSignatureLength || _pubkeyLength != _depositSignatureLength)
            revert MisMatchingInputKeysSize();
        keyCount = _pubkeyLength;
        if (keyCount == 0 || keyCount > inputKeyCountLimit) revert InvalidKeyCount();

        totalKeys = getOperatorTotalKeys(_operatorId);
        uint256 totalNonTerminalKeys = getOperatorTotalNonTerminalKeys(msg.sender, 0, totalKeys);
        if ((totalNonTerminalKeys + keyCount) > maxNonTerminalKeyPerOperator) revert maxKeyLimitReached();

        // check for collateral ETH for adding keys
        if (msg.value != keyCount * collateralETH) revert InvalidBondEthValue();
        //check if operator has enough SD collateral for adding `keyCount` keys
        bool isEnoughCollateral = ISDCollateral(staderConfig.getSDCollateral()).hasEnoughSDCollateral(
            msg.sender,
            _poolId,
            totalNonTerminalKeys + keyCount
        );
        if (!isEnoughCollateral) revert NotEnoughSDCollateral();
    }

    function _sendValue(address _receiver, uint256 _amount) internal {
        if (address(this).balance < _amount) revert InSufficientBalance();

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(_receiver).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }

    // operator in active state
    function _onlyActiveOperator(address _operAddr) internal view returns (uint256 _operatorId) {
        _operatorId = operatorIDByAddress[_operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        if (!operatorStructById[_operatorId].active) revert OperatorIsDeactivate();
    }

    // only valid name with string length limit
    function _onlyValidName(string calldata _name) internal view {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > staderConfig.getOperatorMaxNameLength()) revert NameCrossedMaxLength();
    }

    // checks if validator status enum is not withdrawn ,front run and invalid signature
    function _isNonTerminalValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        return
            !(validator.status == ValidatorStatus.WITHDRAWN ||
                validator.status == ValidatorStatus.FRONT_RUN ||
                validator.status == ValidatorStatus.INVALID_SIGNATURE);
    }

    // checks if validator is active,
    //active validator are those having user deposit staked on beacon chain
    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        return
            !(validator.status == ValidatorStatus.INITIALIZED ||
                validator.status == ValidatorStatus.INVALID_SIGNATURE ||
                validator.status == ValidatorStatus.FRONT_RUN ||
                validator.status == ValidatorStatus.PRE_DEPOSIT ||
                validator.status == ValidatorStatus.WITHDRAWN);
    }

    // decreases the pool total active validator count
    function _decreaseTotalActiveValidatorCount(uint256 _count) internal {
        totalActiveValidatorCount -= _count;
    }

    function _onlyInitializedValidator(uint256 _validatorId) internal view {
        if (_validatorId == 0 || validatorRegistry[_validatorId].status != ValidatorStatus.INITIALIZED)
            revert UNEXPECTED_STATUS();
    }

    function _markValidatorDeposited(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.DEPOSITED;
    }
}
