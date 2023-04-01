// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IPermissionedPool.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IValidatorWithdrawalVault.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPermissionedNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionedNodeRegistry is
    INodeRegistry,
    IPermissionedNodeRegistry,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using Math for uint256;

    uint8 public constant override poolId = 2;

    uint16 public override nextOperatorId;
    uint16 public override inputKeyCountLimit;
    uint16 public override operatorIdForExcessDeposit;
    uint16 public override totalActiveOperatorCount;

    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;
    uint64 public override maxKeyPerOperator;

    IStaderConfig public staderConfig;

    uint256 public override nextValidatorId;
    uint256 public override totalActiveValidatorCount;
    uint256 public VERIFIED_KEYS_BATCH_SIZE;

    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');
    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');
    bytes32 public constant override PERMISSIONED_NODE_REGISTRY_OWNER = keccak256('PERMISSIONED_NODE_REGISTRY_OWNER');

    // mapping of validator ID and Validator struct
    mapping(uint256 => Validator) public override validatorRegistry;
    // mapping of bytes public key and validator Id
    mapping(bytes => uint256) public override validatorIdByPubkey;
    // mapping of operaot ID and Operator struct
    mapping(uint16 => Operator) public override operatorStructById;
    // mapping of operator address and operator Id
    mapping(address => uint16) public override operatorIDByAddress;
    // mapping of whitelisted permissioned node operator
    mapping(address => bool) public override permissionList;
    //mapping of operator wise queued validator IDs arrays
    mapping(uint256 => uint256[]) public override validatorIdsByOperatorId;
    //mapping of operator ID and nextQueuedValidatorIndex
    mapping(uint16 => uint256) public override nextQueuedValidatorIndexByOperatorId;
    mapping(uint256 => uint256) public socializingPoolStateChangeBlock;

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        staderConfig = IStaderConfig(_staderConfig);
        nextOperatorId = 1;
        nextValidatorId = 1;
        operatorIdForExcessDeposit = 1;
        inputKeyCountLimit = 100;
        maxKeyPerOperator = 1000;
        VERIFIED_KEYS_BATCH_SIZE = 50;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @notice white list the permissioned node operator
     * @dev only admin can call, whitelisting a one way change there is no blacklisting
     * @param _permissionedNOs array of permissioned NOs address
     */
    function whitelistPermissionedNOs(address[] calldata _permissionedNOs)
        external
        override
        onlyRole(STADER_MANAGER_BOT)
    {
        for (uint256 i = 0; i < _permissionedNOs.length; i++) {
            permissionList[_permissionedNOs[i]] = true;
            emit OperatorWhitelisted(_permissionedNOs[i]);
        }
    }

    /**
     * @notice onboard a node operator
     * @dev only whitelisted NOs can call
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return feeRecipientAddress fee recipient address for all validator clients
     */
    function onboardNodeOperator(string calldata _operatorName, address payable _operatorRewardAddress)
        external
        override
        whenNotPaused
        returns (address feeRecipientAddress)
    {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_operatorRewardAddress);
        if (!permissionList[msg.sender]) revert NotAPermissionedNodeOperator();
        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();
        feeRecipientAddress = staderConfig.getPermissionedSocializingPool();
        _onboardOperator(_operatorName, _operatorRewardAddress);
        return feeRecipientAddress;
    }

    /**
     * @notice add signing keys
     * @dev only accepts node operator onboarded along with sufficient SD lockup
     * @param _pubkey public key of validators
     * @param _preDepositSignature signature of a validators for 1ETH deposit
     * @param _depositSignature signature of a validator for 31ETH deposit
     */
    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external override whenNotPaused {
        uint16 operatorId = _onlyActiveOperator(msg.sender);
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
                0,
                0,
                0
            );
            validatorIdByPubkey[_pubkey[i]] = nextValidatorId;
            validatorIdsByOperatorId[operatorId].push(nextValidatorId);
            emit AddedValidatorKey(msg.sender, _pubkey[i], nextValidatorId);
            nextValidatorId++;
        }
    }

    /**
     * @notice operator selection logic
     * @dev first iteration is round robin based on capacity,
     * second iteration exhaust the capacity in sequential manner and
     * update the operatorId to pick operator for next sequence in next cycle
     * all array start with index 1
     * @param numValidators validator to deposit with permissioned pool
     * @return selectedOperatorCapacity operator wise count of validator to deposit
     */
    function computeOperatorAllocationForDeposit(uint256 numValidators)
        external
        override
        onlyRole(PERMISSIONED_POOL)
        returns (uint256[] memory selectedOperatorCapacity)
    {
        // nextOperatorId is total operator count plus 1
        selectedOperatorCapacity = new uint256[](nextOperatorId);

        uint256 validatorPerOperator = numValidators / totalActiveOperatorCount;
        uint256[] memory remainingOperatorCapacity = new uint256[](nextOperatorId);
        uint256 totalValidatorToDeposit;

        if (validatorPerOperator != 0) {
            for (uint16 i = 1; i < nextOperatorId; i++) {
                if (!operatorStructById[i].active) continue;
                remainingOperatorCapacity[i] = _getOperatorQueuedValidatorCount(i);
                selectedOperatorCapacity[i] = Math.min(remainingOperatorCapacity[i], validatorPerOperator);
                totalValidatorToDeposit += selectedOperatorCapacity[i];
                remainingOperatorCapacity[i] -= selectedOperatorCapacity[i];
            }
        }

        // check for more validators to deposit and select operators with excess supply in a sequential order
        // and update the starting index of operator for next sequence after every iteration
        if (numValidators > totalValidatorToDeposit) {
            uint16 totalOperators = nextOperatorId - 1;
            uint256 remainingValidatorsToDeposit = numValidators - totalValidatorToDeposit;
            uint16 i = operatorIdForExcessDeposit;
            do {
                if (!operatorStructById[i].active) continue;
                uint256 newSelectedCapacity = Math.min(remainingOperatorCapacity[i], remainingValidatorsToDeposit);
                selectedOperatorCapacity[i] += newSelectedCapacity;
                remainingValidatorsToDeposit -= newSelectedCapacity;
                i = (i % totalOperators) + 1;
                if (remainingValidatorsToDeposit == 0) {
                    operatorIdForExcessDeposit = i;
                    break;
                }
            } while (i != operatorIdForExcessDeposit);
        }
    }

    //oracle report of front run, invalid signature and verified validators
    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkeys,
        bytes[] calldata _frontRunPubkeys,
        bytes[] calldata _invalidSignaturePubkeys
    ) external onlyRole(STADER_ORACLE) {
        uint256 verifiedValidatorsLength = _readyToDepositPubkeys.length;
        if (verifiedValidatorsLength > VERIFIED_KEYS_BATCH_SIZE) revert TooManyVerifiedKeysToDeposit();

        uint256 frontRunValidatorsLength = _frontRunPubkeys.length;
        uint256 invalidSignatureValidatorsLength = _invalidSignaturePubkeys.length;

        //handle the front run validators
        for (uint256 i = 0; i < frontRunValidatorsLength; i++) {
            uint256 validatorId = validatorIdByPubkey[_frontRunPubkeys[i]];
            // only PRE_DEPOSIT status check will also include validatorId = 0 check
            // as status for that will be INITIALIZED(default status)
            _onlyPreDepositValidator(validatorId);
            _handleFrontRun(validatorId);
            emit ValidatorMarkedAsFrontRunned(_frontRunPubkeys[i], validatorId);
        }

        //handle the invalid signature validators
        for (uint256 i = 0; i < invalidSignatureValidatorsLength; i++) {
            uint256 validatorId = validatorIdByPubkey[_invalidSignaturePubkeys[i]];
            // only PRE_DEPOSIT status check will also include validatorId = 0 check
            // as status for that will be INITIALIZED(default status)
            _onlyPreDepositValidator(validatorId);
            validatorRegistry[validatorId].status = ValidatorStatus.INVALID_SIGNATURE;
            emit ValidatorStatusMarkedAsInvalidSignature(_invalidSignaturePubkeys[i], validatorId);
        }
        uint256 totalDefectedKeys = frontRunValidatorsLength + invalidSignatureValidatorsLength;
        _decreaseTotalActiveValidatorCount(totalDefectedKeys);
        address permissionedPool = staderConfig.getPermissionedPool();
        IPermissionedPool(permissionedPool).transferETHOfDefectiveKeysToSSPM(totalDefectedKeys);

        // TODO sanjay update 31ETH limbo
        IPermissionedPool(permissionedPool).fullDepositOnBeaconChain(_readyToDepositPubkeys);
    }

    /**
     * @notice Flag fully withdrawn validators as reported by oracle.
     * @dev list of pubkeys reported by oracle, settle all EL and CL vault balances, revert if terminal validators are reported
     * @param  _pubkeys array of withdrawn validator's pubkey
     */
    function withdrawnValidators(bytes[] calldata _pubkeys) external onlyRole(STADER_ORACLE) {
        uint256 withdrawnValidatorCount = _pubkeys.length;
        for (uint256 i = 0; i < withdrawnValidatorCount; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            if (!_isNonTerminalValidator(validatorId)) revert UNEXPECTED_STATUS();
            Validator memory validator = validatorRegistry[validatorId];
            validator.status = ValidatorStatus.WITHDRAWN;
            validator.withdrawnBlock = block.number;
            IValidatorWithdrawalVault(validator.withdrawVaultAddress).settleFunds();
            uint16 operatorId = uint16(validator.operatorId);
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
     * @notice deactivate a node operator from running new validator clients
     * @dev only accept call from address having `STADER_MANAGER_BOT` role
     * @param _operatorID ID of the operator to deactivate
     */
    function deactivateNodeOperator(uint16 _operatorID) external override onlyRole(STADER_MANAGER_BOT) {
        operatorStructById[_operatorID].active = false;
        totalActiveOperatorCount--;
        emit OperatorDeactivated(_operatorID);
    }

    /**
     * @notice activate a node operator for running new validator clients
     * @dev only accept call from address having `OPERATOR_STATUS_ROLE` role
     * @param _operatorID ID of the operator to activate
     */
    function activateNodeOperator(uint16 _operatorID) external override onlyRole(STADER_MANAGER_BOT) {
        operatorStructById[_operatorID].active = true;
        totalActiveOperatorCount++;
        emit OperatorActivated(_operatorID);
    }

    /**
     * @notice update the `nextQueuedValidatorIndex` for operator
     * @dev only permissioned pool can call
     * @param _operatorID ID of the node operator
     * @param _nextQueuedValidatorIndex updated next index of queued validator per operator
     */
    function updateQueuedValidatorIndex(uint16 _operatorID, uint256 _nextQueuedValidatorIndex)
        external
        override
        onlyRole(PERMISSIONED_POOL)
    {
        nextQueuedValidatorIndexByOperatorId[_operatorID] = _nextQueuedValidatorIndex;
        emit UpdatedQueuedValidatorIndex(_operatorID, _nextQueuedValidatorIndex);
    }

    /**
     * @notice sets the depositTime for a validator and update status to DEPOSITED
     * @dev only permissioned pool can call
     * @param _validatorId ID of the validator
     */
    function updateDepositStatusAndBlock(uint256 _validatorId) external override onlyRole(PERMISSIONED_POOL) {
        validatorRegistry[_validatorId].depositBlock = block.number;
        _markValidatorDeposited(_validatorId);
        emit UpdatedValidatorDepositBlock(_validatorId, block.number);
    }

    /**
     * @notice update the status of a validator to `PRE_DEPOSIT`
     * @dev only `PERMISSIONED_POOL` role can call
     * @param _pubkey public key of the validator
     */
    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external override onlyRole(PERMISSIONED_POOL) {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        validatorRegistry[validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        emit MarkedValidatorStatusAsPreDeposit(_pubkey);
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
        uint16 operatorId = operatorIDByAddress[msg.sender];
        operatorStructById[operatorId].operatorName = _operatorName;
        operatorStructById[operatorId].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorDetails(msg.sender, _operatorName, _rewardAddress);
    }

    /**
     * @notice update the maximum non terminal key limit per operator
     * @dev only admin can call
     * @param _maxKeyPerOperator updated maximum non withdrawn key per operator limit
     */
    function updateMaxKeyPerOperator(uint64 _maxKeyPerOperator)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        maxKeyPerOperator = _maxKeyPerOperator;
        emit UpdatedMaxNonTerminalKeyPerOperator(maxKeyPerOperator);
    }

    /**
     * @notice update number of validator keys that can be added in a single tx by the operator
     * @dev only admin can call
     * @param _inputKeyCountLimit updated maximum key limit in the input
     */
    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        inputKeyCountLimit = _inputKeyCountLimit;
        emit UpdatedInputKeyCountLimit(inputKeyCountLimit);
    }

    /**
     * @notice update the max number of verified validator keys reported by oracle
     * @dev only admin can call
     * @param _verifiedKeysBatchSize updated maximum verified key limit in the oracle input
     */
    function updateVerifiedKeysBatchSize(uint256 _verifiedKeysBatchSize)
        external
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        VERIFIED_KEYS_BATCH_SIZE = _verifiedKeysBatchSize;
        emit UpdatedVerifiedKeyBatchSize(_verifiedKeysBatchSize);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
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
        uint16 operatorId = uint16(validatorRegistry[validatorId].operatorId);
        return operatorStructById[operatorId];
    }

    /**
     * @notice increase the total active validator count
     * @dev only permissioned pool calls it when it does the deposit of 1 ETH for validator
     * @param _count count to increase total active validator value
     */
    function increaseTotalActiveValidatorCount(uint256 _count) external override onlyRole(PERMISSIONED_POOL) {
        totalActiveValidatorCount += _count;
        emit IncreasedTotalActiveValidatorCount(totalActiveValidatorCount);
    }

    /**
     * @notice computes total queued keys for permissioned pool
     * @dev compute by looping over operators queued keys count
     * @return _validatorCount queued validator count
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        uint256 totalQueuedValidators;
        for (uint16 i = 1; i < nextOperatorId; i++) {
            if (operatorStructById[i].active) {
                totalQueuedValidators += _getOperatorQueuedValidatorCount(i);
            }
        }
        return totalQueuedValidators;
    }

    /**
     * @notice returns total active keys for permissioned pool
     * @dev return the variable totalActiveValidatorCount
     * @return _validatorCount active validator count
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return totalActiveValidatorCount;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev length of the validatorIds array for an operator
     * @param _operatorId ID of node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) public view override returns (uint256 _totalKeys) {
        _totalKeys = validatorIdsByOperatorId[_operatorId].length;
    }

    /**
     * @notice get the total non terminal keys for an operator
     * //non terminal keys are front run, invalid signature and withdrawn
     * @dev loop over all keys of an operator from start index till
     *  end index (exclusive) to get the count excluding the terminal keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 startIndex,
        uint256 endIndex
    ) public view override returns (uint64) {
        if (startIndex > endIndex) {
            revert InvalidStartAndEndIndex();
        }
        uint16 operatorId = operatorIDByAddress[_nodeOperator];
        uint256 validatorCount = getOperatorTotalKeys(operatorId);
        endIndex = endIndex > validatorCount ? validatorCount : endIndex;
        uint64 totalNonWithdrawnKeyCount;
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 validatorId = validatorIdsByOperatorId[operatorId][i];
            if (_isNonTerminalValidator(validatorId)) {
                totalNonWithdrawnKeyCount++;
            }
        }
        return totalNonWithdrawnKeyCount;
    }

    function getCollateralETH() external pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice returns the operator reward address
     * @param _operatorId operator ID
     */
    function getOperatorRewardAddress(uint16 _operatorId) public view override returns (address payable) {
        return operatorStructById[_operatorId].operatorRewardAddress;
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        _unpause();
    }

    /**
     * @notice returns the validator for which protocol don't have money on execution layer
     * @dev loop over all validator to filter out the initialized, front run and withdrawn and return the rest
     */
    function getAllActiveValidators() public view override returns (Validator[] memory) {
        Validator[] memory validators = new Validator[](totalActiveValidatorCount);
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

    // check for duplicate keys in permissioned node registry
    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return validatorIdByPubkey[_pubkey] != 0;
    }

    // check for only PRE_DEPOSIT state validators
    function onlyPreDepositValidator(bytes calldata _pubkey) external view override {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        _onlyPreDepositValidator(validatorId);
    }

    function _onboardOperator(string calldata _operatorName, address payable _operatorRewardAddress) internal {
        operatorStructById[nextOperatorId] = Operator(true, true, _operatorName, _operatorRewardAddress, msg.sender);
        operatorIDByAddress[msg.sender] = nextOperatorId;
        socializingPoolStateChangeBlock[nextOperatorId] = block.number;
        nextOperatorId++;
        totalActiveOperatorCount++;
        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    // handle front run validator by changing their status and deactivating operator
    function _handleFrontRun(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.FRONT_RUN;
        uint16 operatorId = uint16(validatorRegistry[_validatorId].operatorId);
        operatorStructById[operatorId].active = false;
    }

    // returns operator total queued validator count
    function _getOperatorQueuedValidatorCount(uint16 _operatorId) internal view returns (uint256 _validatorCount) {
        _validatorCount =
            validatorIdsByOperatorId[_operatorId].length -
            nextQueuedValidatorIndexByOperatorId[_operatorId];
    }

    // checks for keys lengths, and if pubkey is already present in stader protocol(not just permissioned pool)
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
        uint16 _operatorId
    ) internal view returns (uint256 keyCount, uint256 totalKeys) {
        if (_pubkeyLength != _preDepositSignatureLength || _pubkeyLength != _depositSignatureLength)
            revert MisMatchingInputKeysSize();
        keyCount = _pubkeyLength;
        if (keyCount == 0 || keyCount > inputKeyCountLimit) revert InvalidKeyCount();

        totalKeys = getOperatorTotalKeys(_operatorId);
        uint256 totalNonTerminalKeys = getOperatorTotalNonTerminalKeys(msg.sender, 0, totalKeys);
        if ((totalNonTerminalKeys + keyCount) > maxKeyPerOperator) revert maxKeyLimitReached();

        //check if operator has enough SD collateral for adding `keyCount` keys
        //TODO sanjay put a comment saying phase1 limit will be 0 for permissioned NOs?
        bool isEnoughCollateral = ISDCollateral(staderConfig.getSDCollateral()).hasEnoughSDCollateral(
            msg.sender,
            _poolId,
            totalNonTerminalKeys + keyCount
        );
        if (!isEnoughCollateral) revert NotEnoughSDCollateral();
    }

    // operator in active state
    function _onlyActiveOperator(address _operAddr) internal view returns (uint16 _operatorId) {
        _operatorId = operatorIDByAddress[_operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        if (!operatorStructById[_operatorId].active) revert OperatorIsDeactivate();
    }

    // checks if validator is active,
    //active validator are those having user deposit staked on beacon chain
    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        return
            !(validator.status == ValidatorStatus.INITIALIZED ||
                validator.status == ValidatorStatus.INVALID_SIGNATURE ||
                validator.status == ValidatorStatus.FRONT_RUN ||
                validator.status == ValidatorStatus.WITHDRAWN);
    }

    // checks if validator status enum is not withdrawn ,front run and invalid signature
    function _isNonTerminalValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        return
            !(validator.status == ValidatorStatus.WITHDRAWN ||
                validator.status == ValidatorStatus.FRONT_RUN ||
                validator.status == ValidatorStatus.INVALID_SIGNATURE);
    }

    // only valid name with string length limit
    function _onlyValidName(string calldata _name) internal view {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > staderConfig.getOperatorMaxNameLength()) revert NameCrossedMaxLength();
    }

    // decreases the pool total active validator count
    function _decreaseTotalActiveValidatorCount(uint256 _count) internal {
        totalActiveValidatorCount -= _count;
    }

    function _onlyPreDepositValidator(uint256 _validatorId) internal view {
        if (validatorRegistry[_validatorId].status != ValidatorStatus.PRE_DEPOSIT) revert UNEXPECTED_STATUS();
    }

    function _markValidatorDeposited(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.DEPOSITED;
    }
}
